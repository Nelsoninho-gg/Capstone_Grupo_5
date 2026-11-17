-- =====================================================================
-- NURYBASE — Base de datos completa en un solo archivo
-- Generado a partir de database/: esquema base, migraciones en orden y funciones.
-- No incluye los ENSAYO (terminan en ROLLBACK), las pruebas ni los datos demo.
-- Tampoco migrations/0004_venta_empleado.sql (ya está dentro de schema_nury.sql) ni
-- functions/cuadrar_y_cerrar_turno.sql (borrador para otro esquema, no lo usa la app).
-- Se aplica sobre una base PostgreSQL vacía:
--   psql -v ON_ERROR_STOP=1 -d <base> -f nurybase_completo.sql
-- =====================================================================

-- Preparación (correr como superusuario, p. ej. postgres) ----------------------------
-- Roles de la API que usan los permisos. En el servidor ya existen; en una base nueva se crean
-- sin login (PostgREST los asume según el token).
DO $$
DECLARE r TEXT;
BEGIN
    FOREACH r IN ARRAY ARRAY['nury_admin', 'nury_cajero', 'nury_bodeguero', 'web_anon'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
            EXECUTE format('CREATE ROLE %I NOLOGIN', r);
        END IF;
    END LOOP;
END;
$$;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
-- Todo el esquema es de nury_admin, como en el servidor: varias migraciones cambian a ese rol.
ALTER SCHEMA public OWNER TO nury_admin;
SET SESSION AUTHORIZATION nury_admin;

-- Contenido:
--   01. database/schema_nury.sql
--   02. database/migrations/0002_add_anulada_motivo_to_ventas.sql
--   03. database/migrations/0003_apertura_control_turno.sql
--   04. database/migrations/0004_stock_producto_reventa.sql
--   05. database/migrations/0005_ajuste_stock.sql
--   06. database/migrations/0005_venta_empleado_descuento.sql
--   07. database/migrations/0006_facturas_compra_productos.sql
--   08. database/migrations/0006_listar_empleados.sql
--   09. database/migrations/0007_reponer_stock_anulacion_venta.sql
--   10. database/migrations/0007_venta_especial.sql
--   11. database/migrations/0008_ajuste_stock_idempotente.sql
--   12. database/migrations/20260928_crear_usuario_rpc.sql
--   13. database/migrations/20260928_roles_usuarios.sql
--   14. database/migrations/20260930_sucursales_api.sql
--   15. database/migrations/20261012_permisos_cajero.sql
--   16. database/migrations/20261012_recuperar_turno.sql
--   17. database/migrations/20261016_facturas_xml_pendientes.sql
--   18. database/migrations/20261017_equivalencias_lineas_xml.sql
--   19. database/migrations/20261017_ingresar_factura_xml.sql
--   20. database/migrations/20261017_permisos_ingreso_facturas.sql
--   21. database/migrations/20261017_stock_insuficiente_venta.sql
--   22. database/migrations/20261020_consulta_ingresos_factura.sql
--   23. database/migrations/20261020_consultar_factura_ingresada.sql
--   24. database/migrations/20261020_intentos_factura_duplicada.sql
--   25. database/migrations/20261020_versiones_receta.sql
--   26. database/migrations/20261021_historial_ajustes_bodeguero.sql
--   27. database/migrations/20261021_modelo_articulos.sql
--   28. database/migrations/20261021_permiso_recetas_bodeguero.sql
--   29. database/migrations/20261022_almuerzo_unico_por_dia.sql
--   30. database/migrations/20261022_almuerzos_empleado.sql
--   31. database/migrations/20261022_movimientos_timestamptz.sql
--   32. database/migrations/20261022_registrar_almuerzo_empleado.sql
--   33. database/migrations/20261022_stock_minimo_bodeguero.sql
--   34. database/migrations/20261023_unidad_fija_ingrediente.sql
--   35. database/migrations/20261023_unidad_lamina.sql
--   36. database/migrations/20261024_estado_stock.sql
--   37. database/migrations/20261025_catalogo_materias_primas_bodeguero.sql
--   38. database/migrations/20261026_movimientos_articulos.sql
--   39. database/migrations/20261026_venta_idempotente.sql
--   40. database/migrations/20261027_detalle_venta_una_vez.sql
--   41. database/migrations/20261027_nombres_unicos_normalizados.sql
--   42. database/migrations/20261027_receta_ingrediente_activo.sql
--   43. database/migrations/20261027_receta_unidad_base.sql
--   44. database/migrations/20261027_venta_concurrente.sql
--   45. database/migrations/20261027_version_inventario.sql
--   46. database/migrations/20261030_articulos_por_comprar.sql
--   47. database/migrations/20261101_direcciones_factura_xml.sql
--   48. database/migrations/20261104_reporte_cajeros.sql
--   49. database/migrations/20261104_reporte_productos_sucursal.sql
--   50. database/migrations/20261104_reporte_ventas_sucursal.sql
--   51. database/migrations/20261105_consumo_diario_articulos.sql
--   52. database/migrations/20261105_cuadratura_ventas_stock.sql
--   53. database/migrations/20261105_guardar_promocion.sql
--   54. database/migrations/20261105_promociones.sql
--   55. database/migrations/20261105_promociones_margen.sql
--   56. database/migrations/20261105_promociones_permisos.sql
--   57. database/migrations/20261105_promociones_venta.sql
--   58. database/migrations/20261105_promociones_vigentes.sql
--   59. database/migrations/20261105_reporte_promociones.sql
--   60. database/migrations/20261106_costo_actual_productos.sql
--   61. database/migrations/20261106_reporte_cajeros_turno.sql
--   62. database/migrations/20261108_promociones_sucursales.sql


-- #####################################################################
-- 01. database/schema_nury.sql
-- #####################################################################

-- =====================================================================
-- NURY CAFETERÍA — Esquema de Base de Datos: Inventario + Ventas
-- Motor: PostgreSQL (compatible con mínimos ajustes en MySQL/SQLite)
-- Versión 3 — ajusta facturas_compra/detalle_factura_compra a una factura
-- real (descuentos, flete, impuesto específico, código del proveedor y
-- presentación de compra), a partir de una factura real de Coca-Cola Andina.
-- =====================================================================
--
-- IDEA CENTRAL DEL MODELO
-- ------------------------
-- 1. Todo lo que se compra (pan, queso, café, leche, azúcar, servilletas, etc.)
--    es un INGREDIENTE. Es la única fuente de verdad del stock físico.
-- 2. Lo que se vende (un sándwich, un café con leche, una porción de torta)
--    es un PRODUCTO. Un producto NO tiene stock propio: tiene una RECETA
--    que dice cuánto de cada ingrediente necesita.
-- 3. Al registrar una FACTURA DE COMPRA -> sube el stock de los ingredientes
--    EN LA SUCURSAL que recibió la mercadería.
-- 4. Al registrar una VENTA -> se recorre la receta del producto vendido y
--    se descuenta automáticamente el stock de cada ingrediente involucrado,
--    en la sucursal donde ocurrió la venta.
-- 5. Todo movimiento de stock (por compra, venta o ajuste manual/merma)
--    queda registrado en un "kardex" (movimientos_stock) para trazabilidad.
--
-- QUÉ CAMBIA EN ESTA VERSIÓN respecto a la v1
-- --------------------------------------------
-- - El stock deja de vivir en `ingredientes` y pasa a `stock_sucursal`:
--   cada sucursal tiene su propia cantidad física del mismo ingrediente
--   del catálogo. `ingredientes` queda como catálogo puro (nombre, unidad,
--   costo promedio), no como inventario.
-- - `facturas_compra` y `ventas` ahora quedan atadas a una `sucursal_id`,
--   lo que hace posible el reporte de ventas por sucursal.
-- - Se agrega `usuarios` (cajeros/administradores) con rol, credenciales
--   y ciclo de vida (activo/inactivo, nunca borrado si tiene historial),
--   lo que hace posible el reporte de desempeño por cajero.
-- - Se agrega `promociones`, con vigencia por fecha/hora/día de semana,
--   y `detalle_venta` ahora guarda precio de lista y precio aplicado por
--   separado para poder medir el impacto real de cada promoción.
--
-- QUÉ CAMBIA EN LA VERSIÓN 3 (a partir de una factura real de proveedor)
-- -----------------------------------------------------------------------
-- Una factura real de un proveedor como Coca-Cola Andina trae columnas que
-- v1/v2 no contemplaban: código propio del proveedor por producto, la
-- presentación de compra (cajas de N botellas, no la unidad del ingrediente),
-- descuento por línea, flete por línea, y un impuesto específico (el
-- impuesto adicional a bebidas analcohólicas/alcohólicas, ILA/IABA en Chile)
-- que también va por línea. Se agrega:
-- - `codigos_proveedor_ingrediente`: mapea el código SKU de cada proveedor
--   (ej. '122951') a nuestro ingrediente del catálogo, para que el futuro
--   OCR pueda identificar la línea sin adivinar por el nombre.
-- - `detalle_factura_compra` gana `codigo_proveedor`, `presentacion_compra`,
--   `unidades_por_presentacion`, `descuento_porcentaje`, `descuento_monto`,
--   `flete` e `impuesto_especifico`. El antiguo `subtotal` (generado) se
--   reemplaza por `subtotal_neto` (cantidad × precio − descuento) y
--   `total_linea` (subtotal_neto + flete + impuesto_especifico).
-- - `facturas_compra` gana `monto_neto`, `monto_iva` y
--   `monto_impuestos_especificos`, para que el total de la cabecera se
--   pueda cuadrar contra el desglose real que trae la factura.
-- - El trigger de compra ahora calcula el costo promedio del ingrediente
--   sobre el COSTO REAL POR UNIDAD (incluye descuento, flete e impuesto
--   específico prorrateados), no sobre el precio de lista — así el margen
--   de `v_costo_producto` refleja lo que Nury realmente pagó, no el precio
--   antes de cargos.
--
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;


-- ---------------------------------------------------------------------
-- 1. UNIDADES DE MEDIDA
-- ---------------------------------------------------------------------
CREATE TABLE unidades_medida (
    id              SERIAL PRIMARY KEY,
    nombre          VARCHAR(40) NOT NULL UNIQUE,   -- 'Kilogramo', 'Unidad', 'Litro'
    abreviatura     VARCHAR(10) NOT NULL UNIQUE     -- 'kg', 'un', 'L'
);

INSERT INTO unidades_medida (nombre, abreviatura) VALUES
    ('Kilogramo', 'kg'),
    ('Gramo', 'g'),
    ('Litro', 'L'),
    ('Mililitro', 'ml'),
    ('Unidad', 'un'),
    ('Paquete', 'paq');


-- ---------------------------------------------------------------------
-- 2. CATEGORÍAS DE INGREDIENTE (opcional, para orden y reportes)
-- ---------------------------------------------------------------------
CREATE TABLE categorias_ingrediente (
    id      SERIAL PRIMARY KEY,
    nombre  VARCHAR(60) NOT NULL UNIQUE   -- 'Panadería', 'Lácteos', 'Café', 'Insumos'
);


-- ---------------------------------------------------------------------
-- 3. SUCURSALES
-- ---------------------------------------------------------------------
CREATE TABLE sucursales (
    id          SERIAL PRIMARY KEY,
    nombre      VARCHAR(120) NOT NULL UNIQUE
                CONSTRAINT sucursales_nombre_no_vacio CHECK (btrim(nombre) <> ''),
    direccion   VARCHAR(200),
    telefono    VARCHAR(30),
    activo      BOOLEAN NOT NULL DEFAULT TRUE,
    creado_en   TIMESTAMP NOT NULL DEFAULT now()
);

-- Normaliza tanto el alta por RPC como la edición directa de PostgREST.
CREATE OR REPLACE FUNCTION public.fn_normalizar_sucursal()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    NEW.nombre := btrim(NEW.nombre);
    NEW.direccion := NULLIF(btrim(NEW.direccion), '');
    NEW.telefono := NULLIF(btrim(NEW.telefono), '');
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_normalizar_sucursal
BEFORE INSERT OR UPDATE OF nombre, direccion, telefono ON public.sucursales
FOR EACH ROW EXECUTE FUNCTION public.fn_normalizar_sucursal();

-- Alta de sucursales con el mismo contrato de filas que crear_usuario.
CREATE OR REPLACE FUNCTION public.crear_sucursal(
    p_nombre VARCHAR(120),
    p_direccion VARCHAR(200) DEFAULT NULL,
    p_telefono VARCHAR(30) DEFAULT NULL,
    p_activo BOOLEAN DEFAULT TRUE
)
RETURNS TABLE (
    id INTEGER,
    nombre VARCHAR(120),
    direccion VARCHAR(200),
    telefono VARCHAR(30),
    activo BOOLEAN,
    creado_en TIMESTAMP
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
BEGIN
    RETURN QUERY
    INSERT INTO public.sucursales AS s (nombre, direccion, telefono, activo)
    VALUES (p_nombre, p_direccion, p_telefono, p_activo)
    RETURNING s.id, s.nombre, s.direccion, s.telefono, s.activo, s.creado_en;
END;
$$;

REVOKE ALL ON FUNCTION public.crear_sucursal(
    character varying, character varying, character varying, boolean
) FROM PUBLIC;


-- ---------------------------------------------------------------------
-- 4. PROVEEDORES  (sirven a todas las sucursales, no son exclusivos de una)
-- ---------------------------------------------------------------------
CREATE TABLE proveedores (
    id          SERIAL PRIMARY KEY,
    nombre      VARCHAR(120) NOT NULL,
    rut         VARCHAR(20) UNIQUE,   -- llave natural del proveedor chileno; permite NULL, evita duplicados al recargar
    telefono    VARCHAR(30),
    email       VARCHAR(120),
    creado_en   TIMESTAMP NOT NULL DEFAULT now()
);


-- ---------------------------------------------------------------------
-- 5. INGREDIENTES  (catálogo — el stock físico vive en stock_sucursal)
-- ---------------------------------------------------------------------
CREATE TABLE ingredientes (
    id                      SERIAL PRIMARY KEY,
    nombre                  VARCHAR(120) NOT NULL UNIQUE,   -- 'Pan de molde', 'Queso gauda laminado'
    categoria_id            INTEGER REFERENCES categorias_ingrediente(id),
    unidad_id               INTEGER NOT NULL REFERENCES unidades_medida(id),
    costo_unitario_promedio NUMERIC(12,2) NOT NULL DEFAULT 0,  -- costo promedio ponderado global (todas las sucursales)
    codigo_barras           VARCHAR(64) UNIQUE,   -- EAN/UPC físico del ingrediente (para escaneo al recibir factura)
    activo                  BOOLEAN NOT NULL DEFAULT TRUE,
    creado_en               TIMESTAMP NOT NULL DEFAULT now(),
    actualizado_en          TIMESTAMP NOT NULL DEFAULT now()
);

CREATE INDEX idx_ingredientes_activo ON ingredientes(activo);


-- ---------------------------------------------------------------------
-- 6. STOCK POR SUCURSAL  (el inventario físico real, uno por local)
-- ---------------------------------------------------------------------
CREATE TABLE stock_sucursal (
    id              SERIAL PRIMARY KEY,
    ingrediente_id  INTEGER NOT NULL REFERENCES ingredientes(id),
    sucursal_id     INTEGER NOT NULL REFERENCES sucursales(id),
    stock_actual    NUMERIC(12,3) NOT NULL DEFAULT 0,
    stock_minimo    NUMERIC(12,3) NOT NULL DEFAULT 0,   -- umbral de reposición, propio de cada local
    actualizado_en  TIMESTAMP NOT NULL DEFAULT now(),
    UNIQUE (ingrediente_id, sucursal_id)
);

CREATE INDEX idx_stock_sucursal_sucursal ON stock_sucursal(sucursal_id);


-- ---------------------------------------------------------------------
-- 7. FACTURAS DE COMPRA (cabecera)  -- esto es lo que se "escanea"
-- ---------------------------------------------------------------------
CREATE TABLE facturas_compra (
    id                          SERIAL PRIMARY KEY,
    proveedor_id                INTEGER REFERENCES proveedores(id),
    sucursal_id                 INTEGER NOT NULL REFERENCES sucursales(id),  -- local que recibió la mercadería
    numero_factura              VARCHAR(60),
    fecha_factura               DATE NOT NULL,
    fecha_registro              TIMESTAMP NOT NULL DEFAULT now(),
    monto_neto                  NUMERIC(12,2),   -- neto antes de IVA e impuestos específicos (campo "NETO" de la factura)
    monto_iva                   NUMERIC(12,2),   -- IVA 19%
    monto_impuestos_especificos NUMERIC(12,2),   -- suma de impuestos adicionales (IABA/ILA en bebidas, u otros rubros)
    monto_total                 NUMERIC(12,2),   -- total final de la factura (campo "TOTAL")
    archivo_url                 TEXT,                 -- link/ruta a la imagen o PDF escaneado (respaldo)
    estado                      VARCHAR(20) NOT NULL DEFAULT 'confirmada'
                                    CHECK (estado IN ('pendiente_revision','confirmada','anulada')),
    creado_en                   TIMESTAMP NOT NULL DEFAULT now()
);

-- Mapea el código SKU propio de cada proveedor (columna "COD" de la factura)
-- a nuestro ingrediente del catálogo. El mismo ingrediente puede tener un
-- código distinto según el proveedor; esto es lo que permite que un OCR
-- futuro identifique la línea sin adivinar por el nombre/descripción.
CREATE TABLE codigos_proveedor_ingrediente (
    id                      SERIAL PRIMARY KEY,
    proveedor_id            INTEGER NOT NULL REFERENCES proveedores(id),
    ingrediente_id          INTEGER NOT NULL REFERENCES ingredientes(id),
    codigo                  VARCHAR(30) NOT NULL,        -- ej. '122951'
    descripcion_proveedor   VARCHAR(150),                 -- ej. 'Coca Cola PT591cc x 6' (texto tal cual en la factura)
    UNIQUE (proveedor_id, codigo)
);

-- Detalle de la factura: cada línea es un ingrediente comprado
CREATE TABLE detalle_factura_compra (
    id                          SERIAL PRIMARY KEY,
    factura_id                  INTEGER NOT NULL REFERENCES facturas_compra(id) ON DELETE CASCADE,
    ingrediente_id              INTEGER NOT NULL REFERENCES ingredientes(id),
    codigo_proveedor            VARCHAR(30),      -- código tal cual aparece en ESTA factura (columna "COD")
    presentacion_compra         VARCHAR(40),      -- ej. 'Caja x6' — cómo se compró, no necesariamente la unidad base
    unidades_por_presentacion   NUMERIC(10,2) DEFAULT 1,  -- ej. 6 botellas por caja; solo referencia/auditoría
    cantidad                    NUMERIC(12,3) NOT NULL CHECK (cantidad > 0),  -- SIEMPRE en la unidad base del ingrediente
    unidad_id                   INTEGER NOT NULL REFERENCES unidades_medida(id),
    precio_unitario             NUMERIC(12,2) NOT NULL,  -- precio de lista por unidad base, antes de descuento
    descuento_porcentaje        NUMERIC(5,2) NOT NULL DEFAULT 0,   -- "TASA DESCTO%"
    descuento_monto             NUMERIC(12,2) NOT NULL DEFAULT 0,  -- "MONTO DESCTO"
    flete                       NUMERIC(12,2) NOT NULL DEFAULT 0,  -- "FLETE" de esta línea
    impuesto_especifico         NUMERIC(12,2) NOT NULL DEFAULT 0,  -- "IMPTO ESPECIF." (ILA/IABA u otro impuesto adicional)
    subtotal_neto  NUMERIC(12,2) GENERATED ALWAYS AS ((cantidad * precio_unitario) - descuento_monto) STORED,
    total_linea    NUMERIC(12,2) GENERATED ALWAYS AS
                        ((cantidad * precio_unitario) - descuento_monto + flete + impuesto_especifico) STORED
);


-- ---------------------------------------------------------------------
-- 8. PRODUCTOS  (lo que se vende: sándwiches, cafés, pasteles, etc.)
-- ---------------------------------------------------------------------
CREATE TABLE productos (
    id              SERIAL PRIMARY KEY,
    nombre          VARCHAR(120) NOT NULL UNIQUE,   -- 'Sándwich de queso', 'Café con leche'
    categoria       VARCHAR(60),                     -- 'Sándwiches', 'Bebidas calientes', 'Pastelería'
    precio_venta    NUMERIC(12,2) NOT NULL,
    codigo_barras   VARCHAR(64) UNIQUE,   -- EAN/UPC físico del producto (para escaneo directo en el POS)
    activo          BOOLEAN NOT NULL DEFAULT TRUE,
    creado_en       TIMESTAMP NOT NULL DEFAULT now()
);


-- ---------------------------------------------------------------------
-- 9. RECETAS (BOM: Bill of Materials) -- el corazón del descuento automático
--    Une un producto con los ingredientes (y cantidades) que necesita.
--    Es a nivel de catálogo: la misma receta aplica en todas las sucursales.
-- ---------------------------------------------------------------------
CREATE TABLE recetas (
    id                  SERIAL PRIMARY KEY,
    producto_id         INTEGER NOT NULL REFERENCES productos(id) ON DELETE CASCADE,
    ingrediente_id      INTEGER NOT NULL REFERENCES ingredientes(id),
    cantidad_necesaria  NUMERIC(12,3) NOT NULL CHECK (cantidad_necesaria > 0),
    unidad_id           INTEGER NOT NULL REFERENCES unidades_medida(id),
    UNIQUE (producto_id, ingrediente_id)
);

-- Ejemplo de datos (ilustrativo, no se ejecuta automáticamente):
-- INSERT INTO productos (nombre, categoria, precio_venta) VALUES ('Sándwich de queso', 'Sándwiches', 3500);
-- INSERT INTO recetas (producto_id, ingrediente_id, cantidad_necesaria, unidad_id)
--   VALUES (<id_sandwich>, <id_pan>, 2, <id_unidad_un>),
--          (<id_sandwich>, <id_queso>, 30, <id_unidad_g>);


-- ---------------------------------------------------------------------
-- 10. USUARIOS (cajeros y administradores)
-- ---------------------------------------------------------------------
CREATE TABLE usuarios (
    id                      SERIAL PRIMARY KEY,
    nombre                  VARCHAR(120) NOT NULL,
    identificador_acceso    VARCHAR(120) NOT NULL UNIQUE,   -- usuario, RUT o email de login
    password_hash           TEXT NOT NULL,                   -- nunca texto plano (bcrypt/argon2, etc.)
    rol                     VARCHAR(20) NOT NULL CHECK (rol IN ('admin','administrador','cajero','bodeguero')),
    sucursal_id             INTEGER REFERENCES sucursales(id),  -- local fijo del cajero; NULL permitido solo para administradores
    debe_cambiar_password   BOOLEAN NOT NULL DEFAULT TRUE,    -- fuerza cambio en primer login
    activo                  BOOLEAN NOT NULL DEFAULT TRUE,    -- deshabilitar = false, nunca borrar si tiene ventas
    creado_en               TIMESTAMP NOT NULL DEFAULT now(),
    actualizado_en          TIMESTAMP NOT NULL DEFAULT now(),
    CHECK (rol <> 'cajero' OR sucursal_id IS NOT NULL)  -- todo cajero debe tener una sucursal fija asignada
);

-- Alta segura de usuarios para PostgREST: la contraseña solo se recibe en
-- esta función y se almacena como hash bcrypt; nunca se devuelve al cliente.
CREATE OR REPLACE FUNCTION crear_usuario(
    p_nombre VARCHAR(120),
    p_identificador_acceso VARCHAR(120),
    p_contrasena TEXT,
    p_rol VARCHAR(20),
    p_sucursal_id INTEGER,
    p_debe_cambiar_password BOOLEAN,
    p_activo BOOLEAN
)
RETURNS TABLE (
    id INTEGER,
    nombre VARCHAR(120),
    identificador_acceso VARCHAR(120),
    rol VARCHAR(20),
    sucursal_id INTEGER,
    debe_cambiar_password BOOLEAN,
    activo BOOLEAN,
    creado_en TIMESTAMP,
    actualizado_en TIMESTAMP
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_nombre IS NULL OR btrim(p_nombre) = '' THEN
        RAISE EXCEPTION 'El nombre es obligatorio';
    END IF;

    IF p_identificador_acceso IS NULL OR btrim(p_identificador_acceso) = '' THEN
        RAISE EXCEPTION 'El usuario de acceso es obligatorio';
    END IF;

    IF p_contrasena IS NULL OR length(p_contrasena) < 4 THEN
        RAISE EXCEPTION 'La contraseña debe tener al menos 4 caracteres';
    END IF;

    RETURN QUERY
    INSERT INTO usuarios AS u (
        nombre,
        identificador_acceso,
        password_hash,
        rol,
        sucursal_id,
        debe_cambiar_password,
        activo
    )
    VALUES (
        p_nombre,
        p_identificador_acceso,
        crypt(p_contrasena, gen_salt('bf')),
        p_rol,
        p_sucursal_id,
        p_debe_cambiar_password,
        p_activo
    )
    RETURNING u.id, u.nombre, u.identificador_acceso, u.rol, u.sucursal_id,
              u.debe_cambiar_password, u.activo, u.creado_en, u.actualizado_en;
END;
$$;

-- (Se eliminó usuario_sucursal: cada cajero trabaja en una única sucursal,
-- así que basta con el campo usuarios.sucursal_id — no hace falta una
-- relación muchos-a-muchos.)

-- Turnos: permite medir desempeño por turno y no solo por día calendario
CREATE TABLE turnos (
    id              SERIAL PRIMARY KEY,
    usuario_id      INTEGER NOT NULL REFERENCES usuarios(id),
    sucursal_id     INTEGER NOT NULL REFERENCES sucursales(id),
    hora_inicio     TIMESTAMP NOT NULL,
    hora_fin        TIMESTAMP,   -- NULL mientras el turno sigue abierto
    creado_en       TIMESTAMP NOT NULL DEFAULT now()
);

-- Auditoría: quién cambió qué campo de qué usuario, y cuándo
CREATE TABLE auditoria_usuarios (
    id                  SERIAL PRIMARY KEY,
    usuario_id          INTEGER NOT NULL REFERENCES usuarios(id),
    accion              VARCHAR(20) NOT NULL CHECK (accion IN ('creacion','edicion','deshabilitacion','reactivacion')),
    campo_modificado    VARCHAR(60),
    valor_anterior      TEXT,
    valor_nuevo         TEXT,
    realizado_por       INTEGER REFERENCES usuarios(id),   -- quién hizo el cambio (no puede ser el mismo usuario_id)
    creado_en           TIMESTAMP NOT NULL DEFAULT now()
);


-- ---------------------------------------------------------------------
-- 11. PROMOCIONES (H5.2) -- ver migración 20261105_promociones.sql.
--     Rigen solas dentro de su ventana [inicio, termino), en una sucursal o en todas.
-- ---------------------------------------------------------------------
CREATE TABLE promociones (
    id                      SERIAL PRIMARY KEY,
    nombre                  VARCHAR(120) NOT NULL CHECK (btrim(nombre) <> ''),  -- 'Combo sándwich + café'
    tipo                    VARCHAR(20) NOT NULL
                                CHECK (tipo IN ('porcentaje','monto_fijo')),
    valor_descuento         NUMERIC(12,2) NOT NULL,          -- % si tipo='porcentaje', $ si 'monto_fijo'
    inicio                  TIMESTAMPTZ NOT NULL,            -- rige desde (incluido)
    termino                 TIMESTAMPTZ NOT NULL,            -- hasta (no incluido)
    prioridad               INTEGER NOT NULL DEFAULT 0,      -- mayor prioridad gana si dos promos aplican a la vez
    combinable_con_otras    BOOLEAN NOT NULL DEFAULT FALSE,
    activa                  BOOLEAN NOT NULL DEFAULT TRUE,   -- interruptor manual, además de la vigencia programada
    creado_por              INTEGER REFERENCES usuarios(id), -- solo administradores crean promociones (regla de aplicación)
    creado_en               TIMESTAMP NOT NULL DEFAULT now(),
    CHECK (valor_descuento > 0 AND (tipo <> 'porcentaje' OR valor_descuento <= 100)),
    CHECK (termino > inicio)
);

CREATE INDEX idx_promociones_vigencia ON promociones(inicio, termino);

-- Sucursales donde rige cada promoción. Sin filas = todas las sucursales (también las nuevas).
CREATE TABLE promocion_sucursales (
    promocion_id    INTEGER NOT NULL REFERENCES promociones(id) ON DELETE CASCADE,
    sucursal_id     INTEGER NOT NULL REFERENCES sucursales(id),
    PRIMARY KEY (promocion_id, sucursal_id)
);

CREATE INDEX idx_promocion_sucursales_sucursal ON promocion_sucursales(sucursal_id);

-- Productos que forman la promoción y sus unidades (ej. 1 sándwich + 1 café).
-- Al menos uno por promoción (trigger diferido de la migración).
CREATE TABLE promocion_productos (
    promocion_id    INTEGER NOT NULL REFERENCES promociones(id) ON DELETE CASCADE,
    producto_id     INTEGER NOT NULL REFERENCES productos(id),
    cantidad        INTEGER NOT NULL DEFAULT 1 CHECK (cantidad > 0),
    PRIMARY KEY (promocion_id, producto_id)
);

CREATE INDEX idx_promocion_productos_producto ON promocion_productos(producto_id);

-- Registro de alertas cuando una promoción deja el precio bajo el costo de receta (no bloquea, solo avisa)
CREATE TABLE alertas_margen (
    id              SERIAL PRIMARY KEY,
    promocion_id    INTEGER REFERENCES promociones(id),
    producto_id     INTEGER NOT NULL REFERENCES productos(id),
    costo_receta    NUMERIC(12,2) NOT NULL,
    precio_aplicado NUMERIC(12,2) NOT NULL,
    venta_id        INTEGER,
    creado_en       TIMESTAMP NOT NULL DEFAULT now()
);


-- ---------------------------------------------------------------------
-- 12. VENTAS (cabecera del ticket/boleta)
-- ---------------------------------------------------------------------
CREATE TABLE ventas (
    id              SERIAL PRIMARY KEY,
    sucursal_id     INTEGER NOT NULL REFERENCES sucursales(id),
    cajero_id       INTEGER REFERENCES usuarios(id),   -- NULL = venta sin cajero atribuido (se reporta aparte)
    fecha_venta     TIMESTAMP NOT NULL DEFAULT now(),
    medio_pago      VARCHAR(30),        -- 'efectivo', 'debito', 'credito', 'transferencia'
    total           NUMERIC(12,2) NOT NULL DEFAULT 0,
    anulada         BOOLEAN NOT NULL DEFAULT FALSE,
    anulada_en      TIMESTAMP,
    anulada_por     INTEGER REFERENCES usuarios(id),
    anulada_motivo  TEXT,
    -- Venta a empleados (H2.12): ver migración 0004_venta_empleado.sql
    tipo_venta           VARCHAR(20) NOT NULL DEFAULT 'normal'
                             CHECK (tipo_venta IN ('normal','empleado')),
    empleado_id          INTEGER REFERENCES usuarios(id),   -- quién compra en una venta a empleado
    descuento_porcentaje NUMERIC(5,2) NOT NULL DEFAULT 0 CHECK (descuento_porcentaje BETWEEN 0 AND 100),
    descuento_monto      NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (descuento_monto >= 0),
    codigo_venta         VARCHAR(20) GENERATED ALWAYS AS (
                             CASE WHEN tipo_venta = 'empleado' THEN 'EMP-' ELSE 'TK-' END || id
                         ) STORED,                            -- TK-<id> normal, EMP-<id> empleado
    venta_especial       BOOLEAN GENERATED ALWAYS AS (tipo_venta = 'empleado') STORED,  -- true = con descuento (0007)
    creado_en       TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT ventas_tipo_venta_consistente CHECK (
        (tipo_venta = 'normal' AND empleado_id IS NULL AND descuento_porcentaje = 0 AND descuento_monto = 0)
        OR (tipo_venta = 'empleado' AND empleado_id IS NOT NULL)
    )
);

CREATE INDEX idx_ventas_sucursal_fecha ON ventas(sucursal_id, fecha_venta);
CREATE INDEX idx_ventas_cajero_fecha ON ventas(cajero_id, fecha_venta);
CREATE INDEX idx_ventas_tipo_venta ON ventas(tipo_venta);

CREATE TABLE detalle_venta (
    id              SERIAL PRIMARY KEY,
    venta_id        INTEGER NOT NULL REFERENCES ventas(id) ON DELETE CASCADE,
    producto_id     INTEGER NOT NULL REFERENCES productos(id),
    promocion_id    INTEGER REFERENCES promociones(id),   -- NULL = se vendió a precio de lista
    cantidad        NUMERIC(12,3) NOT NULL CHECK (cantidad > 0),
    precio_lista    NUMERIC(12,2) NOT NULL,   -- precio normal del producto al momento de la venta
    precio_unitario NUMERIC(12,2) NOT NULL,   -- precio realmente cobrado (con promoción aplicada, si corresponde)
    subtotal        NUMERIC(12,2) GENERATED ALWAYS AS (cantidad * precio_unitario) STORED,
    -- H5.2 T07 (migración 20261105_promociones_margen.sql)
    costo_unitario  NUMERIC(12,2),   -- costo al vender (receta o último costo de compra); NULL si no hay
    descuento_unitario NUMERIC(12,2) GENERATED ALWAYS AS (
        CASE WHEN promocion_id IS NULL THEN 0 ELSE precio_lista - precio_unitario END) STORED,
    margen_sacrificado NUMERIC(12,2) GENERATED ALWAYS AS (   -- margen que se dejó de ganar por la promoción
        CASE WHEN promocion_id IS NULL THEN 0 ELSE (precio_lista - precio_unitario) * cantidad END) STORED
);


-- ---------------------------------------------------------------------
-- 13. MOVIMIENTOS DE STOCK (kardex) -- historial de TODO cambio de inventario,
--     ahora también identificado por sucursal.
-- ---------------------------------------------------------------------
CREATE TABLE movimientos_stock (
    id                  SERIAL PRIMARY KEY,
    ingrediente_id      INTEGER NOT NULL REFERENCES ingredientes(id),
    sucursal_id         INTEGER NOT NULL REFERENCES sucursales(id),
    tipo_movimiento     VARCHAR(20) NOT NULL
                            CHECK (tipo_movimiento IN ('compra','venta','ajuste','merma')),
    cantidad            NUMERIC(12,3) NOT NULL,   -- positivo = entrada, negativo = salida
    stock_resultante    NUMERIC(12,3) NOT NULL,   -- stock del ingrediente en esa sucursal después del movimiento
    referencia_tipo     VARCHAR(30),               -- 'factura_compra', 'venta', 'ajuste_manual'
    referencia_id       INTEGER,                   -- id de la factura/venta/ajuste que originó el movimiento
    nota                TEXT,
    creado_en           TIMESTAMP NOT NULL DEFAULT now()
);

CREATE INDEX idx_movimientos_ingrediente_sucursal ON movimientos_stock(ingrediente_id, sucursal_id, creado_en);

-- ---------------------------------------------------------------------
-- 14. ALMUERZOS DE EMPLEADOS (H2.13) -- consumo interno sin cobro.
--     No es una venta: no se suma a ventas, caja ni reportes de venta.
--     Ver migración 20261022_almuerzos_empleado.sql.
-- ---------------------------------------------------------------------
CREATE TABLE almuerzos_empleado (
    id              SERIAL PRIMARY KEY,
    sucursal_id     INTEGER NOT NULL REFERENCES sucursales(id),
    empleado_id     INTEGER NOT NULL REFERENCES usuarios(id),   -- quién almuerza
    cajero_id       INTEGER NOT NULL REFERENCES usuarios(id),   -- quién lo registra
    fecha           DATE NOT NULL DEFAULT (now() AT TIME ZONE 'America/Santiago')::date,  -- día en hora de Chile
    creado_en       TIMESTAMP NOT NULL DEFAULT now()
);

CREATE INDEX idx_almuerzos_empleado_sucursal_fecha ON almuerzos_empleado(sucursal_id, fecha);
CREATE INDEX idx_almuerzos_empleado_empleado_fecha ON almuerzos_empleado(empleado_id, fecha);

CREATE TABLE almuerzos_empleado_detalle (
    id              SERIAL PRIMARY KEY,
    almuerzo_id     INTEGER NOT NULL REFERENCES almuerzos_empleado(id) ON DELETE CASCADE,
    producto_id     INTEGER NOT NULL REFERENCES productos(id),
    cantidad        NUMERIC(12,3) NOT NULL CHECK (cantidad > 0),
    UNIQUE (almuerzo_id, producto_id)
);

CREATE INDEX idx_almuerzos_empleado_detalle_producto ON almuerzos_empleado_detalle(producto_id);


-- =====================================================================
-- TRIGGERS: automatizan el descuento/reposición de stock
-- =====================================================================

-- ---------------------------------------------------------------------
-- A) Al insertar una línea de FACTURA DE COMPRA -> sube stock del ingrediente
--    EN LA SUCURSAL de la factura, y recalcula costo promedio ponderado global.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_aplicar_compra() RETURNS TRIGGER AS $$
DECLARE
    v_sucursal_id    INTEGER;
    v_stock_previo   NUMERIC(12,3);
    v_costo_previo   NUMERIC(12,2);
    v_nuevo_stock    NUMERIC(12,3);
    v_nuevo_costo    NUMERIC(12,2);
    v_costo_real_linea NUMERIC(12,4);  -- costo real por unidad base de ESTA compra (con descuento, flete e impuesto)
BEGIN
    SELECT sucursal_id INTO v_sucursal_id FROM facturas_compra WHERE id = NEW.factura_id;

    -- Asegura que exista la fila de stock para ese ingrediente en esa sucursal
    INSERT INTO stock_sucursal (ingrediente_id, sucursal_id, stock_actual, stock_minimo)
    VALUES (NEW.ingrediente_id, v_sucursal_id, 0, 0)
    ON CONFLICT (ingrediente_id, sucursal_id) DO NOTHING;

    SELECT stock_actual INTO v_stock_previo
      FROM stock_sucursal
     WHERE ingrediente_id = NEW.ingrediente_id AND sucursal_id = v_sucursal_id
     FOR UPDATE;

    SELECT costo_unitario_promedio INTO v_costo_previo
      FROM ingredientes WHERE id = NEW.ingrediente_id
      FOR UPDATE;

    v_nuevo_stock := v_stock_previo + NEW.cantidad;

    -- Costo real por unidad de ESTA línea: precio de lista, menos descuento, más flete e
    -- impuesto específico prorrateados sobre la cantidad — lo que realmente costó cada unidad puesta en la sucursal.
    v_costo_real_linea := NEW.total_linea / NEW.cantidad;

    -- Costo promedio ponderado global: (stock_previo*costo_previo + compra*costo_real) / stock_nuevo
    IF v_nuevo_stock > 0 THEN
        v_nuevo_costo := ((v_stock_previo * v_costo_previo) + (NEW.cantidad * v_costo_real_linea)) / v_nuevo_stock;
    ELSE
        v_nuevo_costo := v_costo_real_linea;
    END IF;

    UPDATE stock_sucursal
       SET stock_actual = v_nuevo_stock,
           actualizado_en = now()
     WHERE ingrediente_id = NEW.ingrediente_id AND sucursal_id = v_sucursal_id;

    UPDATE ingredientes
       SET costo_unitario_promedio = v_nuevo_costo,
           actualizado_en = now()
     WHERE id = NEW.ingrediente_id;

    INSERT INTO movimientos_stock
        (ingrediente_id, sucursal_id, tipo_movimiento, cantidad, stock_resultante, referencia_tipo, referencia_id)
    VALUES
        (NEW.ingrediente_id, v_sucursal_id, 'compra', NEW.cantidad, v_nuevo_stock, 'factura_compra', NEW.factura_id);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_detalle_factura_compra_insert
AFTER INSERT ON detalle_factura_compra
FOR EACH ROW EXECUTE FUNCTION fn_aplicar_compra();


-- ---------------------------------------------------------------------
-- B) Al insertar una línea de VENTA -> descuenta stock de CADA ingrediente
--    de la receta del producto vendido, EN LA SUCURSAL de la venta.
--    Ventas anuladas (ventas.anulada = true) no llegan a esta lógica: el
--    descuento ocurre al insertar detalle_venta, así que anular una venta
--    debe manejarse como una reversión explícita (ver nota abajo).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_aplicar_venta() RETURNS TRIGGER AS $$
DECLARE
    v_sucursal_id  INTEGER;
    receta_row     RECORD;
    v_stock_previo NUMERIC(12,3);
    v_descuento    NUMERIC(12,3);
    v_nuevo_stock  NUMERIC(12,3);
    v_costo_receta NUMERIC(12,2);
BEGIN
    SELECT sucursal_id INTO v_sucursal_id FROM ventas WHERE id = NEW.venta_id;

    FOR receta_row IN
        SELECT ingrediente_id, cantidad_necesaria
          FROM recetas
         WHERE producto_id = NEW.producto_id
    LOOP
        v_descuento := receta_row.cantidad_necesaria * NEW.cantidad;

        INSERT INTO stock_sucursal (ingrediente_id, sucursal_id, stock_actual, stock_minimo)
        VALUES (receta_row.ingrediente_id, v_sucursal_id, 0, 0)
        ON CONFLICT (ingrediente_id, sucursal_id) DO NOTHING;

        SELECT stock_actual INTO v_stock_previo
          FROM stock_sucursal
         WHERE ingrediente_id = receta_row.ingrediente_id AND sucursal_id = v_sucursal_id
         FOR UPDATE;

        v_nuevo_stock := v_stock_previo - v_descuento;

        UPDATE stock_sucursal
           SET stock_actual = v_nuevo_stock,
               actualizado_en = now()
         WHERE ingrediente_id = receta_row.ingrediente_id AND sucursal_id = v_sucursal_id;

        INSERT INTO movimientos_stock
            (ingrediente_id, sucursal_id, tipo_movimiento, cantidad, stock_resultante, referencia_tipo, referencia_id)
        VALUES
            (receta_row.ingrediente_id, v_sucursal_id, 'venta', -v_descuento, v_nuevo_stock, 'venta', NEW.venta_id);
    END LOOP;

    -- Alerta de margen: si la línea trae promoción y el precio aplicado queda bajo el costo de receta, se registra (no bloquea)
    IF NEW.promocion_id IS NOT NULL THEN
        SELECT COALESCE(SUM(r.cantidad_necesaria * i.costo_unitario_promedio), 0)
          INTO v_costo_receta
          FROM recetas r JOIN ingredientes i ON i.id = r.ingrediente_id
         WHERE r.producto_id = NEW.producto_id;

        IF NEW.precio_unitario < v_costo_receta THEN
            INSERT INTO alertas_margen (promocion_id, producto_id, costo_receta, precio_aplicado, venta_id)
            VALUES (NEW.promocion_id, NEW.producto_id, v_costo_receta, NEW.precio_unitario, NEW.venta_id);
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_detalle_venta_insert
AFTER INSERT ON detalle_venta
FOR EACH ROW EXECUTE FUNCTION fn_aplicar_venta();

-- NOTA sobre anulaciones: anular una venta (ventas.anulada = true) es un cambio
-- de estado, no un DELETE. Si el negocio requiere que anular una venta también
-- reponga el stock descontado, eso debe hacerse con una lógica explícita de
-- reversión (un movimiento_stock de signo contrario, tipo 'ajuste'), nunca
-- borrando la venta original, para no perder el rastro de qué pasó.


-- ---------------------------------------------------------------------
-- C) Mantener el total de la venta sincronizado
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_actualizar_total_venta() RETURNS TRIGGER AS $$
BEGIN
    UPDATE ventas
       SET total = (SELECT COALESCE(SUM(subtotal),0) FROM detalle_venta WHERE venta_id = NEW.venta_id)
     WHERE id = NEW.venta_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_actualizar_total_venta
AFTER INSERT ON detalle_venta
FOR EACH ROW EXECUTE FUNCTION fn_actualizar_total_venta();


-- =====================================================================
-- REGISTRO DE VENTAS SIN POS
-- =====================================================================
-- Mientras no exista un POS, cargar una venta a mano significa: insertar en
-- `ventas`, sacar el id con currval(), e insertar una fila en `detalle_venta`
-- POR CADA producto vendido — fácil de errar y lento de escribir todos los
-- días. `fn_registrar_venta` empaqueta eso en una sola llamada: recibe la
-- sucursal, el cajero, el medio de pago y una lista de productos por NOMBRE
-- (no por id), y hace todos los INSERT por dentro. Como sigue usando
-- `INSERT INTO detalle_venta`, los triggers de descuento de stock y de
-- alerta de margen se disparan exactamente igual que si se hubiera hecho a
-- mano. Esta función es el punto de entrada mínimo para vender "sin POS";
-- una futura pantalla o app solo tendría que armar el JSON y llamarla.
CREATE OR REPLACE FUNCTION fn_registrar_venta(
    p_sucursal_id   INTEGER,
    p_cajero_id     INTEGER,
    p_medio_pago    VARCHAR,
    p_items         JSONB   -- ej. '[{"producto":"Sándwich de queso","cantidad":2}]'
                            --      o con precio promocional:
                            --     '[{"producto":"Café con leche","cantidad":1,"precio_unitario":1500,"promocion_id":3}]'
) RETURNS INTEGER AS $$
DECLARE
    v_venta_id      INTEGER;
    item            JSONB;
    v_producto_id   INTEGER;
    v_precio_lista  NUMERIC(12,2);
    v_precio_final  NUMERIC(12,2);
    v_promocion_id  INTEGER;
    v_cantidad      NUMERIC(12,3);
BEGIN
    IF jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'La venta no tiene productos';
    END IF;

    INSERT INTO ventas (sucursal_id, cajero_id, medio_pago)
    VALUES (p_sucursal_id, p_cajero_id, p_medio_pago)
    RETURNING id INTO v_venta_id;

    FOR item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        SELECT id, precio_venta INTO v_producto_id, v_precio_lista
          FROM productos
         WHERE nombre = item->>'producto' AND activo = TRUE;

        IF v_producto_id IS NULL THEN
            RAISE EXCEPTION 'Producto no encontrado o inactivo: %', item->>'producto';
        END IF;

        v_cantidad     := (item->>'cantidad')::NUMERIC;
        v_promocion_id := NULLIF(item->>'promocion_id', '')::INTEGER;
        v_precio_final := COALESCE((item->>'precio_unitario')::NUMERIC, v_precio_lista);

        INSERT INTO detalle_venta (venta_id, producto_id, promocion_id, cantidad, precio_lista, precio_unitario)
        VALUES (v_venta_id, v_producto_id, v_promocion_id, v_cantidad, v_precio_lista, v_precio_final);
    END LOOP;

    RETURN v_venta_id;
END;
$$ LANGUAGE plpgsql;


-- ---------------------------------------------------------------------
-- D) Auditoría de usuarios: registra cambios de rol, estado activo e
--    identificador de acceso cada vez que se edita un usuario.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_auditar_usuario() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.rol IS DISTINCT FROM OLD.rol THEN
        INSERT INTO auditoria_usuarios (usuario_id, accion, campo_modificado, valor_anterior, valor_nuevo)
        VALUES (NEW.id, 'edicion', 'rol', OLD.rol, NEW.rol);
    END IF;

    IF NEW.activo IS DISTINCT FROM OLD.activo THEN
        INSERT INTO auditoria_usuarios (usuario_id, accion, campo_modificado, valor_anterior, valor_nuevo)
        VALUES (NEW.id, CASE WHEN NEW.activo THEN 'reactivacion' ELSE 'deshabilitacion' END,
                'activo', OLD.activo::TEXT, NEW.activo::TEXT);
    END IF;

    IF NEW.identificador_acceso IS DISTINCT FROM OLD.identificador_acceso THEN
        INSERT INTO auditoria_usuarios (usuario_id, accion, campo_modificado, valor_anterior, valor_nuevo)
        VALUES (NEW.id, 'edicion', 'identificador_acceso', OLD.identificador_acceso, NEW.identificador_acceso);
    END IF;

    NEW.actualizado_en := now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_auditar_usuario
BEFORE UPDATE ON usuarios
FOR EACH ROW EXECUTE FUNCTION fn_auditar_usuario();

-- NOTA: "un cajero no puede editar su propio perfil" y "eliminar está bloqueado
-- si tiene ventas asociadas" son reglas de permisos y de flujo de aplicación
-- (quién ejecuta el UPDATE/DELETE), no algo que la base de datos por sí sola
-- pueda saber sin una capa de autenticación. La base solo puede garantizar la
-- parte estructural: por ejemplo, `ventas.cajero_id` referencia a `usuarios(id)`
-- sin ON DELETE CASCADE, así que un intento de borrar un usuario con ventas
-- asociadas falla por restricción de llave foránea en vez de borrar en silencio.


-- =====================================================================
-- VISTAS ÚTILES
-- =====================================================================

-- Ingredientes bajo el mínimo, por sucursal -> lista de reposición local
CREATE VIEW v_ingredientes_bajo_stock AS
SELECT s.sucursal_id, suc.nombre AS sucursal, i.id AS ingrediente_id, i.nombre AS ingrediente,
       s.stock_actual, s.stock_minimo,
       (s.stock_minimo - s.stock_actual) AS cantidad_a_reponer
  FROM stock_sucursal s
  JOIN ingredientes i ON i.id = s.ingrediente_id
  JOIN sucursales suc ON suc.id = s.sucursal_id
 WHERE i.activo = TRUE
   AND s.stock_actual < s.stock_minimo;

-- Costo de receta de cada producto (para saber margen real) — global, no depende de sucursal
CREATE VIEW v_costo_producto AS
SELECT p.id AS producto_id, p.nombre AS producto,
       SUM(r.cantidad_necesaria * i.costo_unitario_promedio) AS costo_receta,
       p.precio_venta,
       p.precio_venta - SUM(r.cantidad_necesaria * i.costo_unitario_promedio) AS margen_estimado
  FROM productos p
  JOIN recetas r ON r.producto_id = p.id
  JOIN ingredientes i ON i.id = r.ingrediente_id
 GROUP BY p.id, p.nombre, p.precio_venta;

-- Ventas por sucursal (excluye ventas anuladas)
CREATE VIEW v_ventas_por_sucursal AS
SELECT v.sucursal_id, s.nombre AS sucursal,
       COUNT(DISTINCT v.id) AS tickets,
       SUM(v.total) AS total_vendido,
       ROUND(SUM(v.total) / NULLIF(COUNT(DISTINCT v.id), 0), 2) AS ticket_promedio
  FROM ventas v
  JOIN sucursales s ON s.id = v.sucursal_id
 WHERE v.anulada = FALSE
 GROUP BY v.sucursal_id, s.nombre;

-- Desempeño por cajero (excluye ventas anuladas y ventas sin cajero atribuido)
CREATE VIEW v_desempeno_cajero AS
SELECT v.cajero_id, u.nombre AS cajero,
       COUNT(DISTINCT v.id) AS tickets,
       SUM(v.total) AS total_vendido,
       ROUND(SUM(v.total) / NULLIF(COUNT(DISTINCT v.id), 0), 2) AS ticket_promedio
  FROM ventas v
  JOIN usuarios u ON u.id = v.cajero_id
 WHERE v.anulada = FALSE
   AND v.cajero_id IS NOT NULL
 GROUP BY v.cajero_id, u.nombre;


-- #####################################################################
-- 02. database/migrations/0002_add_anulada_motivo_to_ventas.sql
-- #####################################################################

-- =====================================================================
-- Migración: agrega ventas.anulada_motivo
--
-- Por qué: al anular una venta se debe registrar el motivo, además de
-- quién (anulada_por) y cuándo (anulada_en), para que la anulación
-- quede trazable.
-- =====================================================================

ALTER TABLE ventas
    ADD COLUMN IF NOT EXISTS anulada_motivo TEXT;

COMMENT ON COLUMN ventas.anulada_motivo IS
    'Motivo ingresado al anular la venta. Nulo si la venta no está anulada.';


-- #####################################################################
-- 03. database/migrations/0003_apertura_control_turno.sql
-- #####################################################################

-- 2.11 — Apertura y control de turno de caja.
--
-- Resuelve los criterios de aceptación que hoy no se cumplen:
--   1. Registrar cajero, sucursal, fecha/hora y monto inicial al abrir turno.
--   2. No permitir más de un turno activo para el mismo cajero y sucursal.
--   3. Bloquear ventas si no existe un turno activo autorizado.
--   4. Bloquear nuevas ventas después del cierre del turno.
--
-- Decisiones confirmadas (2026-10-01):
--   - monto_inicial es obligatorio en cada apertura, pero 0 es un valor válido.
--   - Abrir turno duplicado (mismo cajero + sucursal con uno ya activo) se
--     rechaza con un error claro, no se reutiliza el turno existente.
--   - Se agrega ventas.turno_id para poder asociar cada venta a su turno.
--
-- No toca fn_registrar_venta en su firma: sigue recibiendo los mismos
-- parámetros que ya usa el frontend; internamente ahora busca el turno
-- activo del cajero y rechaza la venta si no existe uno.

BEGIN;

-- 1) Columnas nuevas -------------------------------------------------------

ALTER TABLE public.turnos
    ADD COLUMN IF NOT EXISTS monto_inicial NUMERIC(12,2) NOT NULL DEFAULT 0
        CONSTRAINT turnos_monto_inicial_no_negativo CHECK (monto_inicial >= 0);

-- Sin DEFAULT: las ventas históricas quedan con turno_id NULL; las nuevas
-- siempre lo van a tener porque fn_registrar_venta lo exige.
ALTER TABLE public.ventas
    ADD COLUMN IF NOT EXISTS turno_id INTEGER REFERENCES public.turnos(id);

CREATE INDEX IF NOT EXISTS idx_ventas_turno_id ON public.ventas(turno_id);

-- 2) Un solo turno activo por cajero + sucursal -----------------------------
-- Defensa a nivel de base de datos además de la validación en fn_abrir_turno;
-- cubre condiciones de carrera (dos aperturas casi simultáneas).
CREATE UNIQUE INDEX IF NOT EXISTS turnos_activo_unico
    ON public.turnos (usuario_id, sucursal_id)
    WHERE hora_fin IS NULL;

-- 3) Abrir turno -------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_abrir_turno(
    p_usuario_id INTEGER,
    p_sucursal_id INTEGER,
    p_monto_inicial NUMERIC
)
RETURNS public.turnos
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $function$
DECLARE
    v_turno public.turnos%ROWTYPE;
BEGIN
    IF p_monto_inicial IS NULL OR p_monto_inicial < 0 THEN
        RAISE EXCEPTION 'El monto inicial es obligatorio y no puede ser negativo'
            USING ERRCODE = '22023';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.turnos
         WHERE usuario_id = p_usuario_id
           AND sucursal_id = p_sucursal_id
           AND hora_fin IS NULL
    ) THEN
        RAISE EXCEPTION 'Ya existe un turno activo para este cajero en esta sucursal'
            USING ERRCODE = '23505';
    END IF;

    INSERT INTO public.turnos (usuario_id, sucursal_id, hora_inicio, monto_inicial)
    VALUES (p_usuario_id, p_sucursal_id, clock_timestamp(), p_monto_inicial)
    RETURNING * INTO v_turno;

    RETURN v_turno;
EXCEPTION
    WHEN unique_violation THEN
        -- Se perdió la carrera contra el índice único (dos aperturas casi
        -- simultáneas): mismo mensaje que la validación explícita de arriba.
        RAISE EXCEPTION 'Ya existe un turno activo para este cajero en esta sucursal'
            USING ERRCODE = '23505';
END;
$function$;

-- 4) Cerrar turno --------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_cerrar_turno(
    p_turno_id INTEGER
)
RETURNS public.turnos
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $function$
DECLARE
    v_turno public.turnos%ROWTYPE;
BEGIN
    UPDATE public.turnos
       SET hora_fin = clock_timestamp()
     WHERE id = p_turno_id
       AND hora_fin IS NULL
    RETURNING * INTO v_turno;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El turno no existe o ya estaba cerrado'
            USING ERRCODE = '22023';
    END IF;

    RETURN v_turno;
END;
$function$;

-- 5) fn_registrar_venta ahora exige turno activo -------------------------------
-- Misma firma que antes (no rompe el frontend actual). La única diferencia
-- es que ahora busca el turno activo del cajero/sucursal y lo asocia a la
-- venta; si no hay turno activo, rechaza la venta en vez de registrarla.

CREATE OR REPLACE FUNCTION public.fn_registrar_venta(
    p_sucursal_id INTEGER,
    p_cajero_id INTEGER,
    p_medio_pago CHARACTER VARYING,
    p_items JSONB
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'pg_catalog', 'public', 'pg_temp'
AS $function$
DECLARE
    v_venta_id      INTEGER;
    v_turno_id      INTEGER;
    item            JSONB;
    v_producto_id   INTEGER;
    v_precio_lista  NUMERIC(12,2);
    v_precio_final  NUMERIC(12,2);
    v_promocion_id  INTEGER;
    v_cantidad      NUMERIC(12,3);
BEGIN
    IF jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'La venta no tiene productos';
    END IF;

    SELECT id INTO v_turno_id
      FROM public.turnos
     WHERE usuario_id = p_cajero_id
       AND sucursal_id = p_sucursal_id
       AND hora_fin IS NULL
     ORDER BY hora_inicio DESC
     LIMIT 1;

    IF v_turno_id IS NULL THEN
        RAISE EXCEPTION 'No hay un turno activo para este cajero en esta sucursal; debes abrir turno antes de vender'
            USING ERRCODE = '28000';
    END IF;

    INSERT INTO ventas (sucursal_id, cajero_id, medio_pago, turno_id)
    VALUES (p_sucursal_id, p_cajero_id, p_medio_pago, v_turno_id)
    RETURNING id INTO v_venta_id;

    FOR item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        SELECT id, precio_venta INTO v_producto_id, v_precio_lista
          FROM productos
         WHERE nombre = item->>'producto' AND activo = TRUE;

        IF v_producto_id IS NULL THEN
            RAISE EXCEPTION 'Producto no encontrado o inactivo: %', item->>'producto';
        END IF;

        v_cantidad     := (item->>'cantidad')::NUMERIC;
        v_promocion_id := NULLIF(item->>'promocion_id', '')::INTEGER;
        v_precio_final := COALESCE((item->>'precio_unitario')::NUMERIC, v_precio_lista);

        INSERT INTO detalle_venta (venta_id, producto_id, promocion_id, cantidad, precio_lista, precio_unitario)
        VALUES (v_venta_id, v_producto_id, v_promocion_id, v_cantidad, v_precio_lista, v_precio_final);
    END LOOP;

    RETURN v_venta_id;
END;
$function$;

-- 6) Permisos ------------------------------------------------------------------
-- Mismo patrón que fn_registrar_venta: el cajero ejecuta las funciones (que
-- corren SECURITY DEFINER), no necesita grants directos sobre turnos/ventas.
GRANT EXECUTE ON FUNCTION public.fn_abrir_turno(integer, integer, numeric) TO nury_cajero, nury_admin;
GRANT EXECUTE ON FUNCTION public.fn_cerrar_turno(integer) TO nury_cajero, nury_admin;

COMMIT;


-- #####################################################################
-- 04. database/migrations/0004_stock_producto_reventa.sql
-- #####################################################################

-- Stock propio para productos de reventa simple (por sucursal).
--
-- Contexto: hasta ahora solo los ingredientes tenían stock (stock_sucursal) y
-- un producto descontaba únicamente a través de su receta. Un producto sin
-- receta (ej. una bebida envasada) no descontaba nada. Se acordó con el equipo
-- usar una tabla intermedia producto + sucursal, en lugar de crear un
-- "ingrediente espejo" por cada producto de reventa.
--
-- Regla de negocio (confirmada 2026-10-10):
--   - Producto CON receta  = de fabricación propia -> descuenta ingredientes.
--   - Producto SIN receta  = de reventa            -> descuenta su propio stock.
--
-- Contenido:
--   T01  tabla stock_producto_sucursal
--   T02  movimientos_stock admite producto_id (ingrediente_id pasa a nullable)
--   T03  fn_aplicar_venta con la rama de stock propio
--
-- ANTES DE APLICAR EN PRODUCCIÓN:
--   a) Comparar la versión actual de fn_aplicar_venta contra la de este script:
--        SELECT pg_get_functiondef('public.fn_aplicar_venta()'::regprocedure);
--      (la T03 la reemplaza completa; si producción difiere del repo, ajustar).
--   b) Correr primero 0004_stock_producto_reventa.ENSAYO.sql (termina en ROLLBACK).
--   c) Después de aplicar: NOTIFY pgrst, 'reload schema';

BEGIN;

-- T01) Tabla de stock por producto y sucursal ---------------------------------

CREATE TABLE IF NOT EXISTS public.stock_producto_sucursal (
    id              SERIAL PRIMARY KEY,
    producto_id     INTEGER NOT NULL REFERENCES public.productos(id),
    sucursal_id     INTEGER NOT NULL REFERENCES public.sucursales(id),
    stock_actual    NUMERIC(12,3) NOT NULL DEFAULT 0,
    stock_minimo    NUMERIC(12,3) NOT NULL DEFAULT 0,   -- umbral de reposición, propio de cada local
    actualizado_en  TIMESTAMP NOT NULL DEFAULT now(),
    UNIQUE (producto_id, sucursal_id)
);

CREATE INDEX IF NOT EXISTS idx_stock_producto_sucursal_sucursal
    ON public.stock_producto_sucursal(sucursal_id);

-- El trigger de venta corre con los privilegios del dueño de fn_registrar_venta
-- (SECURITY DEFINER). Si esta tabla quedara a nombre de quien aplica la
-- migración, ese rol no podría escribir en ella y fallarían las ventas de todos
-- los productos sin receta. Por eso se deja con el mismo dueño que stock_sucursal.
DO $$
DECLARE
    v_owner TEXT;
BEGIN
    SELECT pg_get_userbyid(relowner) INTO v_owner
      FROM pg_class WHERE oid = 'public.stock_sucursal'::regclass;

    EXECUTE format('ALTER TABLE public.stock_producto_sucursal OWNER TO %I', v_owner);
    EXECUTE format('ALTER SEQUENCE public.stock_producto_sucursal_id_seq OWNER TO %I', v_owner);
END $$;

-- Mismos permisos de lectura/escritura que ya tiene stock_sucursal, sin
-- adivinar roles: se copian desde su ACL. Las escrituras de la app irán por
-- funciones SECURITY DEFINER (venta y, más adelante, ajuste de stock).
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT DISTINCT a.privilege_type, pg_get_userbyid(a.grantee) AS rol
          FROM pg_class c, aclexplode(c.relacl) a
         WHERE c.oid = 'public.stock_sucursal'::regclass
           AND a.grantee <> 0
           AND a.grantee <> c.relowner
    LOOP
        EXECUTE format('GRANT %s ON public.stock_producto_sucursal TO %I',
                       r.privilege_type, r.rol);
    END LOOP;
END $$;

-- T02) Kardex: un movimiento es de un ingrediente O de un producto -------------

ALTER TABLE public.movimientos_stock
    ALTER COLUMN ingrediente_id DROP NOT NULL;

ALTER TABLE public.movimientos_stock
    ADD COLUMN IF NOT EXISTS producto_id INTEGER REFERENCES public.productos(id);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conname = 'movimientos_stock_un_solo_item'
           AND conrelid = 'public.movimientos_stock'::regclass
    ) THEN
        ALTER TABLE public.movimientos_stock
            ADD CONSTRAINT movimientos_stock_un_solo_item
            CHECK ((ingrediente_id IS NULL) <> (producto_id IS NULL));
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_movimientos_producto_sucursal
    ON public.movimientos_stock(producto_id, sucursal_id, creado_en)
    WHERE producto_id IS NOT NULL;

-- T03) fn_aplicar_venta: receta -> ingredientes; sin receta -> stock propio -----
-- La rama con receta es la misma de siempre, sin cambios.

CREATE OR REPLACE FUNCTION public.fn_aplicar_venta() RETURNS TRIGGER AS $$
DECLARE
    v_sucursal_id  INTEGER;
    v_tiene_receta BOOLEAN;
    receta_row     RECORD;
    v_stock_previo NUMERIC(12,3);
    v_descuento    NUMERIC(12,3);
    v_nuevo_stock  NUMERIC(12,3);
    v_costo_receta NUMERIC(12,2);
BEGIN
    SELECT sucursal_id INTO v_sucursal_id FROM ventas WHERE id = NEW.venta_id;

    SELECT EXISTS (SELECT 1 FROM recetas WHERE producto_id = NEW.producto_id)
      INTO v_tiene_receta;

    IF v_tiene_receta THEN
        FOR receta_row IN
            SELECT ingrediente_id, cantidad_necesaria
              FROM recetas
             WHERE producto_id = NEW.producto_id
        LOOP
            v_descuento := receta_row.cantidad_necesaria * NEW.cantidad;

            INSERT INTO stock_sucursal (ingrediente_id, sucursal_id, stock_actual, stock_minimo)
            VALUES (receta_row.ingrediente_id, v_sucursal_id, 0, 0)
            ON CONFLICT (ingrediente_id, sucursal_id) DO NOTHING;

            SELECT stock_actual INTO v_stock_previo
              FROM stock_sucursal
             WHERE ingrediente_id = receta_row.ingrediente_id AND sucursal_id = v_sucursal_id
             FOR UPDATE;

            v_nuevo_stock := v_stock_previo - v_descuento;

            UPDATE stock_sucursal
               SET stock_actual = v_nuevo_stock,
                   actualizado_en = now()
             WHERE ingrediente_id = receta_row.ingrediente_id AND sucursal_id = v_sucursal_id;

            INSERT INTO movimientos_stock
                (ingrediente_id, sucursal_id, tipo_movimiento, cantidad, stock_resultante, referencia_tipo, referencia_id)
            VALUES
                (receta_row.ingrediente_id, v_sucursal_id, 'venta', -v_descuento, v_nuevo_stock, 'venta', NEW.venta_id);
        END LOOP;
    ELSE
        -- Producto de reventa: descuenta su propio stock en la sucursal de la venta.
        v_descuento := NEW.cantidad;

        INSERT INTO stock_producto_sucursal (producto_id, sucursal_id, stock_actual, stock_minimo)
        VALUES (NEW.producto_id, v_sucursal_id, 0, 0)
        ON CONFLICT (producto_id, sucursal_id) DO NOTHING;

        SELECT stock_actual INTO v_stock_previo
          FROM stock_producto_sucursal
         WHERE producto_id = NEW.producto_id AND sucursal_id = v_sucursal_id
         FOR UPDATE;

        v_nuevo_stock := v_stock_previo - v_descuento;

        UPDATE stock_producto_sucursal
           SET stock_actual = v_nuevo_stock,
               actualizado_en = now()
         WHERE producto_id = NEW.producto_id AND sucursal_id = v_sucursal_id;

        INSERT INTO movimientos_stock
            (producto_id, sucursal_id, tipo_movimiento, cantidad, stock_resultante, referencia_tipo, referencia_id)
        VALUES
            (NEW.producto_id, v_sucursal_id, 'venta', -v_descuento, v_nuevo_stock, 'venta', NEW.venta_id);
    END IF;

    -- Alerta de margen: si la línea trae promoción y el precio aplicado queda bajo el costo de receta, se registra (no bloquea)
    IF NEW.promocion_id IS NOT NULL THEN
        SELECT COALESCE(SUM(r.cantidad_necesaria * i.costo_unitario_promedio), 0)
          INTO v_costo_receta
          FROM recetas r JOIN ingredientes i ON i.id = r.ingrediente_id
         WHERE r.producto_id = NEW.producto_id;

        IF NEW.precio_unitario < v_costo_receta THEN
            INSERT INTO alertas_margen (promocion_id, producto_id, costo_receta, precio_aplicado, venta_id)
            VALUES (NEW.promocion_id, NEW.producto_id, v_costo_receta, NEW.precio_unitario, NEW.venta_id);
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMIT;


-- #####################################################################
-- 05. database/migrations/0005_ajuste_stock.sql
-- #####################################################################

-- Ajuste manual de stock (carga inicial, conteo físico, correcciones).
--
-- Una sola función para los dos tipos de ítem con stock:
--   - un INGREDIENTE (stock_sucursal), o
--   - un PRODUCTO DE REVENTA, es decir sin receta (stock_producto_sucursal).
-- Deja siempre el rastro en el kardex (movimientos_stock) con tipo 'ajuste'.
-- No reemplaza a las compras: una factura sigue entrando por fn_aplicar_compra
-- con tipo 'compra'.
--
-- Requiere haber aplicado antes 0004_stock_producto_reventa.sql.
--
-- Semántica: p_cantidad es la DIFERENCIA a aplicar (positiva = entra stock,
-- negativa = sale stock), no el nuevo valor absoluto.
--
-- Después de aplicar: NOTIFY pgrst, 'reload schema';

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_ajustar_stock(
    p_sucursal_id    INTEGER,
    p_cantidad       NUMERIC,
    p_motivo         TEXT,
    p_ingrediente_id INTEGER DEFAULT NULL,
    p_producto_id    INTEGER DEFAULT NULL
)
RETURNS public.movimientos_stock
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $function$
DECLARE
    v_motivo       TEXT := btrim(COALESCE(p_motivo, ''));
    v_stock_previo NUMERIC(12,3);
    v_nuevo_stock  NUMERIC(12,3);
    v_mov          public.movimientos_stock%ROWTYPE;
BEGIN
    -- Debe indicarse exactamente uno de los dos ítems.
    IF (p_ingrediente_id IS NULL) = (p_producto_id IS NULL) THEN
        RAISE EXCEPTION 'Indica un ingrediente o un producto (solo uno de los dos)'
            USING ERRCODE = '22023';
    END IF;

    IF p_cantidad IS NULL OR p_cantidad = 0 THEN
        RAISE EXCEPTION 'La cantidad del ajuste es obligatoria y no puede ser 0'
            USING ERRCODE = '22023';
    END IF;

    IF v_motivo = '' THEN
        RAISE EXCEPTION 'El motivo del ajuste es obligatorio'
            USING ERRCODE = '22023';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.sucursales WHERE id = p_sucursal_id) THEN
        RAISE EXCEPTION 'La sucursal indicada no existe'
            USING ERRCODE = '23503';
    END IF;

    IF p_ingrediente_id IS NOT NULL THEN
        IF NOT EXISTS (SELECT 1 FROM public.ingredientes WHERE id = p_ingrediente_id) THEN
            RAISE EXCEPTION 'El ingrediente indicado no existe'
                USING ERRCODE = '23503';
        END IF;

        INSERT INTO public.stock_sucursal (ingrediente_id, sucursal_id, stock_actual, stock_minimo)
        VALUES (p_ingrediente_id, p_sucursal_id, 0, 0)
        ON CONFLICT (ingrediente_id, sucursal_id) DO NOTHING;

        SELECT stock_actual INTO v_stock_previo
          FROM public.stock_sucursal
         WHERE ingrediente_id = p_ingrediente_id AND sucursal_id = p_sucursal_id
         FOR UPDATE;
    ELSE
        IF NOT EXISTS (SELECT 1 FROM public.productos WHERE id = p_producto_id) THEN
            RAISE EXCEPTION 'El producto indicado no existe'
                USING ERRCODE = '23503';
        END IF;

        -- Un producto con receta no tiene stock propio: su stock son sus ingredientes.
        IF EXISTS (SELECT 1 FROM public.recetas WHERE producto_id = p_producto_id) THEN
            RAISE EXCEPTION 'Este producto tiene receta: su stock se ajusta a través de sus ingredientes'
                USING ERRCODE = '22023';
        END IF;

        INSERT INTO public.stock_producto_sucursal (producto_id, sucursal_id, stock_actual, stock_minimo)
        VALUES (p_producto_id, p_sucursal_id, 0, 0)
        ON CONFLICT (producto_id, sucursal_id) DO NOTHING;

        SELECT stock_actual INTO v_stock_previo
          FROM public.stock_producto_sucursal
         WHERE producto_id = p_producto_id AND sucursal_id = p_sucursal_id
         FOR UPDATE;
    END IF;

    v_nuevo_stock := v_stock_previo + p_cantidad;

    -- Un ajuste de salida no puede dejar el stock en negativo. Una entrada sí se
    -- permite aunque el stock siga negativo (p. ej. para regularizar ventas de prueba).
    IF p_cantidad < 0 AND v_nuevo_stock < 0 THEN
        RAISE EXCEPTION 'El ajuste dejaría el stock en negativo (actual: %, ajuste: %)',
            v_stock_previo, p_cantidad
            USING ERRCODE = '23514';
    END IF;

    IF p_ingrediente_id IS NOT NULL THEN
        UPDATE public.stock_sucursal
           SET stock_actual = v_nuevo_stock, actualizado_en = now()
         WHERE ingrediente_id = p_ingrediente_id AND sucursal_id = p_sucursal_id;
    ELSE
        UPDATE public.stock_producto_sucursal
           SET stock_actual = v_nuevo_stock, actualizado_en = now()
         WHERE producto_id = p_producto_id AND sucursal_id = p_sucursal_id;
    END IF;

    INSERT INTO public.movimientos_stock
        (ingrediente_id, producto_id, sucursal_id, tipo_movimiento, cantidad,
         stock_resultante, referencia_tipo, nota)
    VALUES
        (p_ingrediente_id, p_producto_id, p_sucursal_id, 'ajuste', p_cantidad,
         v_nuevo_stock, 'ajuste_manual', v_motivo)
    RETURNING * INTO v_mov;

    RETURN v_mov;
END;
$function$;

-- Solo roles de inventario. PostgREST publica únicamente lo ejecutable por el rol de la sesión.
REVOKE ALL ON FUNCTION public.fn_ajustar_stock(integer, numeric, text, integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_ajustar_stock(integer, numeric, text, integer, integer)
    TO nury_admin, nury_bodeguero;

COMMIT;


-- #####################################################################
-- 06. database/migrations/0005_venta_empleado_descuento.sql
-- #####################################################################

-- H2.12 T03 — Venta a empleados: cálculo del descuento en el servidor.
--
-- fn_registrar_venta recibe dos parámetros nuevos, ambos opcionales:
--   - p_tipo_venta:  'normal' (por defecto) o 'empleado'.
--   - p_empleado_id: usuario que compra; obligatorio si la venta es a empleado.
--
-- En una venta a empleado la base de datos calcula el descuento fijo del 30%
-- sobre el total de la venta, redondeado a pesos, y guarda:
--   descuento_porcentaje = 30, descuento_monto y total = subtotal − descuento.
-- El porcentaje no se recibe desde el POS: no es editable.
--
-- No modifica precios: detalle_venta conserva precio_lista y precio_unitario
-- de cada producto, y el maestro de productos no se toca.
--
-- El POS actual sigue funcionando sin cambios: si no envía los parámetros
-- nuevos, la venta se registra como 'normal' igual que antes.
--
-- Cuerpo basado en 0003_apertura_control_turno.sql (exige turno activo).
-- Requiere 0004_venta_empleado.sql aplicada antes.

BEGIN;

-- La función original es de nury_admin: se recrea con ese mismo dueño.
SET LOCAL ROLE nury_admin;

-- Agregar parámetros cambia la firma, así que la función se reemplaza.
DROP FUNCTION public.fn_registrar_venta(integer, integer, character varying, jsonb);

CREATE FUNCTION public.fn_registrar_venta(
    p_sucursal_id INTEGER,
    p_cajero_id INTEGER,
    p_medio_pago CHARACTER VARYING,
    p_items JSONB,
    p_tipo_venta CHARACTER VARYING DEFAULT 'normal',
    p_empleado_id INTEGER DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'pg_catalog', 'public', 'pg_temp'
AS $function$
DECLARE
    -- Descuento fijo de venta a empleado (H2.12). Por ahora no es editable.
    c_descuento_empleado CONSTANT NUMERIC(5,2) := 30;

    v_venta_id      INTEGER;
    v_turno_id      INTEGER;
    v_tipo_venta    VARCHAR(20) := COALESCE(p_tipo_venta, 'normal');
    item            JSONB;
    v_producto_id   INTEGER;
    v_precio_lista  NUMERIC(12,2);
    v_precio_final  NUMERIC(12,2);
    v_promocion_id  INTEGER;
    v_cantidad      NUMERIC(12,3);
    v_subtotal      NUMERIC(12,2);
    v_descuento     NUMERIC(12,2);
BEGIN
    IF jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'La venta no tiene productos';
    END IF;

    IF v_tipo_venta NOT IN ('normal', 'empleado') THEN
        RAISE EXCEPTION 'Tipo de venta no válido: %', v_tipo_venta
            USING ERRCODE = '22023';
    END IF;

    IF v_tipo_venta = 'empleado' THEN
        IF p_empleado_id IS NULL THEN
            RAISE EXCEPTION 'Debes indicar el empleado que compra'
                USING ERRCODE = '22023';
        END IF;

        IF NOT EXISTS (
            SELECT 1 FROM public.usuarios WHERE id = p_empleado_id AND activo = TRUE
        ) THEN
            RAISE EXCEPTION 'El empleado no existe o está deshabilitado'
                USING ERRCODE = '22023';
        END IF;
    ELSIF p_empleado_id IS NOT NULL THEN
        RAISE EXCEPTION 'Una venta normal no lleva empleado'
            USING ERRCODE = '22023';
    END IF;

    SELECT id INTO v_turno_id
      FROM public.turnos
     WHERE usuario_id = p_cajero_id
       AND sucursal_id = p_sucursal_id
       AND hora_fin IS NULL
     ORDER BY hora_inicio DESC
     LIMIT 1;

    IF v_turno_id IS NULL THEN
        RAISE EXCEPTION 'No hay un turno activo para este cajero en esta sucursal; debes abrir turno antes de vender'
            USING ERRCODE = '28000';
    END IF;

    INSERT INTO ventas (sucursal_id, cajero_id, medio_pago, turno_id, tipo_venta, empleado_id)
    VALUES (p_sucursal_id, p_cajero_id, p_medio_pago, v_turno_id, v_tipo_venta, p_empleado_id)
    RETURNING id INTO v_venta_id;

    FOR item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        SELECT id, precio_venta INTO v_producto_id, v_precio_lista
          FROM productos
         WHERE nombre = item->>'producto' AND activo = TRUE;

        IF v_producto_id IS NULL THEN
            RAISE EXCEPTION 'Producto no encontrado o inactivo: %', item->>'producto';
        END IF;

        v_cantidad     := (item->>'cantidad')::NUMERIC;
        v_promocion_id := NULLIF(item->>'promocion_id', '')::INTEGER;
        v_precio_final := COALESCE((item->>'precio_unitario')::NUMERIC, v_precio_lista);

        INSERT INTO detalle_venta (venta_id, producto_id, promocion_id, cantidad, precio_lista, precio_unitario)
        VALUES (v_venta_id, v_producto_id, v_promocion_id, v_cantidad, v_precio_lista, v_precio_final);
    END LOOP;

    -- El trigger trg_actualizar_total_venta ya dejó total = suma de los
    -- subtotales. En una venta a empleado se descuenta el 30% sobre ese
    -- total, redondeado a pesos.
    IF v_tipo_venta = 'empleado' THEN
        SELECT COALESCE(SUM(subtotal), 0) INTO v_subtotal
          FROM detalle_venta
         WHERE venta_id = v_venta_id;

        v_descuento := ROUND(v_subtotal * c_descuento_empleado / 100, 0);

        UPDATE ventas
           SET descuento_porcentaje = c_descuento_empleado,
               descuento_monto      = v_descuento,
               total                = v_subtotal - v_descuento
         WHERE id = v_venta_id;
    END IF;

    RETURN v_venta_id;
END;
$function$;

-- Mismos permisos que tenía la función original (PUBLIC, nury_admin y nury_cajero).
GRANT EXECUTE ON FUNCTION public.fn_registrar_venta(integer, integer, character varying, jsonb, character varying, integer)
    TO PUBLIC, nury_admin, nury_cajero;

COMMIT;


-- #####################################################################
-- 07. database/migrations/0006_facturas_compra_productos.sql
-- #####################################################################

-- Facturas de compra con líneas de PRODUCTO (reventa) y presentaciones en caja.
--
-- Contexto: hasta ahora una línea de factura solo podía ser un ingrediente y el
-- trigger de compra solo sumaba a stock_sucursal. Las facturas de proveedores
-- de bebidas (ej. CCU) traen productos de reventa comprados por CAJA (1 CJ = 12
-- unidades). Este script deja la base lista para recibirlas:
--
--   T01  detalle_factura_compra admite producto_id (ingrediente_id pasa a
--        nullable, exactamente uno de los dos) y unidad_id solo es obligatoria
--        para ingredientes.
--   T02  Presentaciones: se puede cargar la línea tal como viene impresa
--        (cantidad_presentaciones + precio_presentacion) y la base calcula las
--        unidades base, el precio por unidad y, si falta, el monto del descuento.
--   T03  codigos_proveedor_producto: código SKU del proveedor -> producto.
--   T04  fn_aplicar_compra con la rama de producto: suma a
--        stock_producto_sucursal, deja kardex con producto_id y actualiza
--        productos.precio_compra al ÚLTIMO costo real por unidad.
--
-- Reglas (confirmadas 2026-10-10):
--   - El costo de compra del producto = último costo real por unidad
--     (precio con descuento + flete + impuesto específico de la línea, sin IVA).
--   - La cantidad se carga en cajas y la base convierte a unidades.
--   - Un producto CON receta no se compra: su stock sale de sus ingredientes.
--
-- REQUIERE: 0004_stock_producto_reventa.sql aplicado antes.
--
-- ANTES DE APLICAR EN PRODUCCIÓN:
--   a) Revisar la función de compra actual (T04 la reemplaza completa; sus
--      atributos SECURITY DEFINER / search_path se conservan automáticamente):
--        SELECT pg_get_functiondef('public.fn_aplicar_compra()'::regprocedure);
--   b) Revisar las columnas reales del detalle:
--        SELECT column_name, data_type, is_nullable
--          FROM information_schema.columns
--         WHERE table_name = 'detalle_factura_compra' ORDER BY ordinal_position;
--   c) Correr primero 0006_facturas_compra_productos.ENSAYO.sql (termina en ROLLBACK).
--   d) Después de aplicar: NOTIFY pgrst, 'reload schema';
--
-- Limitaciones conocidas (no se resuelven aquí):
--   - Anular una factura (estado = 'anulada') NO revierte el stock; igual que hoy
--     con los ingredientes.
--   - precio_unitario tiene 2 decimales: una caja dividida en unidades puede
--     perder centavos (ej. 5.251 / 12 = 437,58). Es una diferencia de fracciones
--     de peso por línea.
--   - El flete de la factura se reparte a mano en la columna `flete` de cada línea.

BEGIN;

-- Algunas bases ya tienen precio_compra (la agregó otro integrante); en las que
-- no, se crea. Si ya existe, esta sentencia no hace nada.
ALTER TABLE public.productos
    ADD COLUMN IF NOT EXISTS precio_compra NUMERIC(12,2);

-- T01) Líneas de producto en el detalle ----------------------------------------

ALTER TABLE public.detalle_factura_compra
    ALTER COLUMN ingrediente_id DROP NOT NULL;

ALTER TABLE public.detalle_factura_compra
    ADD COLUMN IF NOT EXISTS producto_id INTEGER REFERENCES public.productos(id);

ALTER TABLE public.detalle_factura_compra
    ALTER COLUMN unidad_id DROP NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conrelid = 'public.detalle_factura_compra'::regclass
                      AND conname = 'detalle_factura_compra_un_solo_item') THEN
        ALTER TABLE public.detalle_factura_compra
            ADD CONSTRAINT detalle_factura_compra_un_solo_item
            CHECK ((ingrediente_id IS NULL) <> (producto_id IS NULL));
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conrelid = 'public.detalle_factura_compra'::regclass
                      AND conname = 'detalle_factura_compra_unidad_ingrediente') THEN
        -- La unidad de medida solo tiene sentido para ingredientes.
        ALTER TABLE public.detalle_factura_compra
            ADD CONSTRAINT detalle_factura_compra_unidad_ingrediente
            CHECK (ingrediente_id IS NULL OR unidad_id IS NOT NULL);
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_detalle_factura_compra_producto
    ON public.detalle_factura_compra(producto_id) WHERE producto_id IS NOT NULL;

-- T02) Presentaciones (cajas) ---------------------------------------------------

ALTER TABLE public.detalle_factura_compra
    ADD COLUMN IF NOT EXISTS cantidad_presentaciones NUMERIC(12,3),  -- ej. 7 (cajas), tal como viene en la factura
    ADD COLUMN IF NOT EXISTS precio_presentacion     NUMERIC(12,2);  -- ej. 5139 (precio de una caja), antes de descuento

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conrelid = 'public.detalle_factura_compra'::regclass
                      AND conname = 'detalle_factura_compra_presentacion_check') THEN
        ALTER TABLE public.detalle_factura_compra
            ADD CONSTRAINT detalle_factura_compra_presentacion_check
            CHECK ((cantidad_presentaciones IS NULL OR cantidad_presentaciones > 0)
               AND (precio_presentacion IS NULL OR precio_presentacion >= 0));
    END IF;
END $$;

-- Se ejecuta ANTES de insertar: completa cantidad / precio_unitario /
-- descuento_monto a partir de lo que trae la factura impresa. Las columnas
-- generadas (subtotal_neto, total_linea) se calculan después, con los valores ya
-- completados. Si la línea ya viene en unidades base, no cambia nada.
CREATE OR REPLACE FUNCTION public.fn_normalizar_detalle_factura()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
    IF NEW.cantidad_presentaciones IS NOT NULL THEN
        IF COALESCE(NEW.unidades_por_presentacion, 0) <= 0 THEN
            RAISE EXCEPTION 'Indica cuántas unidades trae cada presentación (caja)'
                USING ERRCODE = '22023';
        END IF;
        NEW.cantidad := NEW.cantidad_presentaciones * NEW.unidades_por_presentacion;
    END IF;

    IF NEW.precio_presentacion IS NOT NULL THEN
        IF COALESCE(NEW.unidades_por_presentacion, 0) <= 0 THEN
            RAISE EXCEPTION 'Indica cuántas unidades trae cada presentación (caja)'
                USING ERRCODE = '22023';
        END IF;
        NEW.precio_unitario := ROUND(NEW.precio_presentacion / NEW.unidades_por_presentacion, 2);
    END IF;

    -- Si la factura informa solo el porcentaje de descuento, se calcula el monto.
    IF COALESCE(NEW.descuento_monto, 0) = 0
       AND COALESCE(NEW.descuento_porcentaje, 0) > 0
       AND NEW.cantidad IS NOT NULL
       AND NEW.precio_unitario IS NOT NULL THEN
        NEW.descuento_monto := ROUND(NEW.cantidad * NEW.precio_unitario * NEW.descuento_porcentaje / 100, 2);
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_detalle_factura_compra_normalizar ON public.detalle_factura_compra;
CREATE TRIGGER trg_detalle_factura_compra_normalizar
BEFORE INSERT ON public.detalle_factura_compra
FOR EACH ROW EXECUTE FUNCTION public.fn_normalizar_detalle_factura();

-- T03) Códigos de proveedor para productos -------------------------------------

CREATE TABLE IF NOT EXISTS public.codigos_proveedor_producto (
    id                          SERIAL PRIMARY KEY,
    proveedor_id                INTEGER NOT NULL REFERENCES public.proveedores(id),
    producto_id                 INTEGER NOT NULL REFERENCES public.productos(id),
    codigo                      VARCHAR(30) NOT NULL,      -- ej. 'INT1-871207' (columna "Código" de la factura)
    descripcion_proveedor       VARCHAR(150),               -- texto tal cual en la factura
    unidades_por_presentacion   NUMERIC(10,2) NOT NULL DEFAULT 1 CHECK (unidades_por_presentacion > 0),  -- ej. 12 por caja
    UNIQUE (proveedor_id, codigo)
);

CREATE INDEX IF NOT EXISTS idx_codigos_proveedor_producto_producto
    ON public.codigos_proveedor_producto(producto_id);

-- Mismo dueño y mismos permisos que el mapeo equivalente de ingredientes.
DO $$
DECLARE
    v_owner TEXT;
    r       RECORD;
BEGIN
    SELECT pg_get_userbyid(relowner) INTO v_owner
      FROM pg_class WHERE oid = 'public.codigos_proveedor_ingrediente'::regclass;

    EXECUTE format('ALTER TABLE public.codigos_proveedor_producto OWNER TO %I', v_owner);
    EXECUTE format('ALTER SEQUENCE public.codigos_proveedor_producto_id_seq OWNER TO %I', v_owner);

    FOR r IN
        SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(a.grantee)) END AS grantee,
               a.privilege_type
          FROM pg_class c, LATERAL aclexplode(c.relacl) a
         WHERE c.oid = 'public.codigos_proveedor_ingrediente'::regclass
           AND a.grantee <> c.relowner
    LOOP
        EXECUTE format('GRANT %s ON public.codigos_proveedor_producto TO %s', r.privilege_type, r.grantee);
    END LOOP;
END $$;

-- T04) fn_aplicar_compra con la rama de producto -------------------------------

-- CREATE OR REPLACE reinicia los atributos de la función; se guardan los de la
-- versión actual (SECURITY DEFINER, search_path) para reponerlos después.
CREATE TEMP TABLE _atributos_fn_compra ON COMMIT DROP AS
SELECT prosecdef, proconfig
  FROM pg_proc
 WHERE oid = 'public.fn_aplicar_compra()'::regprocedure;

CREATE OR REPLACE FUNCTION public.fn_aplicar_compra() RETURNS TRIGGER AS $$
DECLARE
    v_sucursal_id    INTEGER;
    v_stock_previo   NUMERIC(12,3);
    v_costo_previo   NUMERIC(12,2);
    v_nuevo_stock    NUMERIC(12,3);
    v_nuevo_costo    NUMERIC(12,2);
    v_costo_real_linea NUMERIC(12,4);  -- costo real por unidad base de ESTA compra (con descuento, flete e impuesto)
BEGIN
    SELECT sucursal_id INTO v_sucursal_id FROM facturas_compra WHERE id = NEW.factura_id;

    -- Costo real por unidad de ESTA línea: precio de lista, menos descuento, más flete e
    -- impuesto específico prorrateados sobre la cantidad — lo que realmente costó cada unidad puesta en la sucursal.
    v_costo_real_linea := NEW.total_linea / NEW.cantidad;

    IF NEW.ingrediente_id IS NOT NULL THEN
        -- Asegura que exista la fila de stock para ese ingrediente en esa sucursal
        INSERT INTO stock_sucursal (ingrediente_id, sucursal_id, stock_actual, stock_minimo)
        VALUES (NEW.ingrediente_id, v_sucursal_id, 0, 0)
        ON CONFLICT (ingrediente_id, sucursal_id) DO NOTHING;

        SELECT stock_actual INTO v_stock_previo
          FROM stock_sucursal
         WHERE ingrediente_id = NEW.ingrediente_id AND sucursal_id = v_sucursal_id
         FOR UPDATE;

        SELECT costo_unitario_promedio INTO v_costo_previo
          FROM ingredientes WHERE id = NEW.ingrediente_id
          FOR UPDATE;

        v_nuevo_stock := v_stock_previo + NEW.cantidad;

        -- Costo promedio ponderado global: (stock_previo*costo_previo + compra*costo_real) / stock_nuevo
        IF v_nuevo_stock > 0 THEN
            v_nuevo_costo := ((v_stock_previo * v_costo_previo) + (NEW.cantidad * v_costo_real_linea)) / v_nuevo_stock;
        ELSE
            v_nuevo_costo := v_costo_real_linea;
        END IF;

        UPDATE stock_sucursal
           SET stock_actual = v_nuevo_stock,
               actualizado_en = now()
         WHERE ingrediente_id = NEW.ingrediente_id AND sucursal_id = v_sucursal_id;

        UPDATE ingredientes
           SET costo_unitario_promedio = v_nuevo_costo,
               actualizado_en = now()
         WHERE id = NEW.ingrediente_id;

        INSERT INTO movimientos_stock
            (ingrediente_id, sucursal_id, tipo_movimiento, cantidad, stock_resultante, referencia_tipo, referencia_id)
        VALUES
            (NEW.ingrediente_id, v_sucursal_id, 'compra', NEW.cantidad, v_nuevo_stock, 'factura_compra', NEW.factura_id);
    ELSE
        -- Producto de reventa: stock propio por sucursal.
        IF EXISTS (SELECT 1 FROM recetas WHERE producto_id = NEW.producto_id) THEN
            RAISE EXCEPTION 'Este producto tiene receta: no se compra directamente, su stock sale de sus ingredientes'
                USING ERRCODE = '22023';
        END IF;

        INSERT INTO stock_producto_sucursal (producto_id, sucursal_id, stock_actual, stock_minimo)
        VALUES (NEW.producto_id, v_sucursal_id, 0, 0)
        ON CONFLICT (producto_id, sucursal_id) DO NOTHING;

        SELECT stock_actual INTO v_stock_previo
          FROM stock_producto_sucursal
         WHERE producto_id = NEW.producto_id AND sucursal_id = v_sucursal_id
         FOR UPDATE;

        v_nuevo_stock := v_stock_previo + NEW.cantidad;

        UPDATE stock_producto_sucursal
           SET stock_actual = v_nuevo_stock,
               actualizado_en = now()
         WHERE producto_id = NEW.producto_id AND sucursal_id = v_sucursal_id;

        -- Costo de compra del producto = último costo real por unidad.
        UPDATE productos
           SET precio_compra = ROUND(v_costo_real_linea, 2)
         WHERE id = NEW.producto_id;

        INSERT INTO movimientos_stock
            (producto_id, sucursal_id, tipo_movimiento, cantidad, stock_resultante, referencia_tipo, referencia_id)
        VALUES
            (NEW.producto_id, v_sucursal_id, 'compra', NEW.cantidad, v_nuevo_stock, 'factura_compra', NEW.factura_id);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE
    v_secdef BOOLEAN;
    v_config TEXT[];
    v_item   TEXT;
BEGIN
    SELECT prosecdef, proconfig INTO v_secdef, v_config FROM _atributos_fn_compra;

    IF v_secdef THEN
        ALTER FUNCTION public.fn_aplicar_compra() SECURITY DEFINER;
    END IF;

    IF v_config IS NOT NULL THEN
        FOREACH v_item IN ARRAY v_config LOOP
            EXECUTE format('ALTER FUNCTION public.fn_aplicar_compra() SET %s TO %s',
                           split_part(v_item, '=', 1),
                           substr(v_item, strpos(v_item, '=') + 1));
        END LOOP;
    END IF;
END $$;

COMMIT;


-- #####################################################################
-- 08. database/migrations/0006_listar_empleados.sql
-- #####################################################################

-- H2.12 T01/T04 — Venta a empleados: lista de empleados para el POS.
--
-- El cajero necesita elegir qué empleado compra, pero no debe leer la tabla
-- `usuarios` completa (tiene el hash de la contraseña y datos de acceso).
-- Esta función devuelve solo el id y el nombre de los usuarios activos.
--
-- Requiere 0004_venta_empleado.sql y 0005_venta_empleado_descuento.sql.

BEGIN;

-- Mismo dueño que fn_registrar_venta.
SET LOCAL ROLE nury_admin;

CREATE OR REPLACE FUNCTION public.fn_listar_empleados()
RETURNS TABLE (id INTEGER, nombre VARCHAR)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = 'pg_catalog', 'public', 'pg_temp'
AS $function$
    SELECT u.id, u.nombre
      FROM public.usuarios u
     WHERE u.activo = TRUE
     ORDER BY u.nombre;
$function$;

REVOKE ALL ON FUNCTION public.fn_listar_empleados() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_listar_empleados() TO nury_cajero, nury_admin;

COMMIT;


-- #####################################################################
-- 09. database/migrations/0007_reponer_stock_anulacion_venta.sql
-- #####################################################################

-- H3.2 T08 - Reponer el stock al anular una venta.
--
-- Al anular una venta se devuelve al stock exactamente lo que esa venta
-- descontó, con movimientos de signo contrario en el kardex:
--   - Se leen los movimientos 'venta' que dejó fn_aplicar_venta para esa venta
--     (referencia_tipo = 'venta', referencia_id = id de la venta) y se suma por
--     ítem (ingrediente o producto de reventa) y sucursal.
--   - Por cada ítem se inserta un movimiento 'anulacion_venta' con la cantidad
--     contraria, en la MISMA sucursal del descuento, vinculado a la venta
--     original (mismo referencia_tipo / referencia_id) y se suma al stock.
--   - Se usa el kardex y no la receta actual: si la receta cambió después de la
--     venta, igual se devuelve lo que realmente se descontó.
--   - Una venta sin movimientos (p. ej. anterior al control de stock) se anula
--     igual; simplemente no hay nada que reponer.
--
-- Una sola vez por anulación:
--   - fn_anular_venta ya bloquea la fila de la venta y rechaza las anuladas.
--   - Además, un índice único impide en la base que exista más de una
--     reposición por venta, ítem y sucursal, aunque alguien se salte la función.
--
-- Todo ocurre en la misma transacción que marca la venta como anulada: si la
-- reposición falla, la venta tampoco queda anulada.
--
-- Contenido:
--   T01  tipo de movimiento 'anulacion_venta'
--   T02  índice único de reposición por venta
--   T03  fn_reponer_stock_anulacion (interna, no expuesta en la API)
--   T04  fn_anular_venta llama a la reposición
--
-- Requiere: 0004, 0005, 0006 y 20261012_permisos_cajero.sql.
--
-- ANTES DE APLICAR EN PRODUCCIÓN:
--   a) Comparar fn_anular_venta de producción con la de este script (T04 la
--      reemplaza completa; solo se agrega la llamada a la reposición):
--        SELECT pg_get_functiondef('public.fn_anular_venta(integer,text)'::regprocedure);
--   b) Confirmar el CHECK actual del tipo de movimiento:
--        SELECT conname, pg_get_constraintdef(oid) FROM pg_constraint
--         WHERE conrelid = 'public.movimientos_stock'::regclass AND contype = 'c';
--   c) Correr primero 0007_reponer_stock_anulacion_venta.ENSAYO.sql (termina en ROLLBACK).
--   d) Después de aplicar: NOTIFY pgrst, 'reload schema';

BEGIN;

-- T01) Nuevo tipo de movimiento ------------------------------------------------
-- Se reemplaza el CHECK que lista los tipos (se busca por su definición, sin
-- depender del nombre que le haya puesto Postgres).
DO $$
DECLARE
    v_con TEXT;
BEGIN
    FOR v_con IN
        SELECT conname FROM pg_constraint
         WHERE conrelid = 'public.movimientos_stock'::regclass
           AND contype = 'c'
           AND pg_get_constraintdef(oid) ILIKE '%tipo_movimiento%'
    LOOP
        EXECUTE format('ALTER TABLE public.movimientos_stock DROP CONSTRAINT %I', v_con);
    END LOOP;
END $$;

ALTER TABLE public.movimientos_stock
    ADD CONSTRAINT movimientos_stock_tipo_movimiento_check
    CHECK (tipo_movimiento IN ('compra', 'venta', 'ajuste', 'merma', 'anulacion_venta'));

-- T02) Una sola reposición por venta, ítem y sucursal -------------------------
CREATE UNIQUE INDEX IF NOT EXISTS ux_movimientos_anulacion_venta
    ON public.movimientos_stock (
        referencia_id, sucursal_id,
        COALESCE(ingrediente_id, 0), COALESCE(producto_id, 0)
    )
    WHERE tipo_movimiento = 'anulacion_venta';

-- T03) Reposición del stock de una venta ---------------------------------------
-- Interna: la llama fn_anular_venta. No se expone en PostgREST.
CREATE OR REPLACE FUNCTION public.fn_reponer_stock_anulacion(p_venta_id INTEGER, p_motivo TEXT)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $function$
DECLARE
    mov            RECORD;
    v_reponer      NUMERIC(12,3);
    v_stock_previo NUMERIC(12,3);
    v_nuevo_stock  NUMERIC(12,3);
    v_nota         TEXT := format('Anulación de la venta #%s', p_venta_id)
                           || COALESCE(': ' || NULLIF(btrim(p_motivo), ''), '');
    v_filas        INTEGER := 0;
BEGIN
    IF EXISTS (SELECT 1 FROM public.movimientos_stock
                WHERE tipo_movimiento = 'anulacion_venta'
                  AND referencia_tipo = 'venta'
                  AND referencia_id = p_venta_id) THEN
        RAISE EXCEPTION 'El stock de la venta #% ya fue repuesto', p_venta_id
            USING ERRCODE = '23505';
    END IF;

    -- Orden fijo (ingredientes y luego productos, por id) para evitar bloqueos cruzados.
    FOR mov IN
        SELECT sucursal_id, ingrediente_id, producto_id, SUM(cantidad) AS total
          FROM public.movimientos_stock
         WHERE tipo_movimiento = 'venta'
           AND referencia_tipo = 'venta'
           AND referencia_id = p_venta_id
         GROUP BY sucursal_id, ingrediente_id, producto_id
        HAVING SUM(cantidad) <> 0
         ORDER BY sucursal_id, ingrediente_id NULLS LAST, producto_id NULLS LAST
    LOOP
        v_reponer := -mov.total;   -- la venta descontó (negativo); se devuelve en positivo

        IF mov.ingrediente_id IS NOT NULL THEN
            INSERT INTO public.stock_sucursal (ingrediente_id, sucursal_id, stock_actual, stock_minimo)
            VALUES (mov.ingrediente_id, mov.sucursal_id, 0, 0)
            ON CONFLICT (ingrediente_id, sucursal_id) DO NOTHING;

            SELECT stock_actual INTO v_stock_previo
              FROM public.stock_sucursal
             WHERE ingrediente_id = mov.ingrediente_id AND sucursal_id = mov.sucursal_id
             FOR UPDATE;

            v_nuevo_stock := v_stock_previo + v_reponer;

            UPDATE public.stock_sucursal
               SET stock_actual = v_nuevo_stock, actualizado_en = now()
             WHERE ingrediente_id = mov.ingrediente_id AND sucursal_id = mov.sucursal_id;
        ELSE
            INSERT INTO public.stock_producto_sucursal (producto_id, sucursal_id, stock_actual, stock_minimo)
            VALUES (mov.producto_id, mov.sucursal_id, 0, 0)
            ON CONFLICT (producto_id, sucursal_id) DO NOTHING;

            SELECT stock_actual INTO v_stock_previo
              FROM public.stock_producto_sucursal
             WHERE producto_id = mov.producto_id AND sucursal_id = mov.sucursal_id
             FOR UPDATE;

            v_nuevo_stock := v_stock_previo + v_reponer;

            UPDATE public.stock_producto_sucursal
               SET stock_actual = v_nuevo_stock, actualizado_en = now()
             WHERE producto_id = mov.producto_id AND sucursal_id = mov.sucursal_id;
        END IF;

        INSERT INTO public.movimientos_stock
            (ingrediente_id, producto_id, sucursal_id, tipo_movimiento, cantidad,
             stock_resultante, referencia_tipo, referencia_id, nota)
        VALUES
            (mov.ingrediente_id, mov.producto_id, mov.sucursal_id, 'anulacion_venta', v_reponer,
             v_nuevo_stock, 'venta', p_venta_id, v_nota);

        v_filas := v_filas + 1;
    END LOOP;

    RETURN v_filas;   -- cantidad de ítems repuestos
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_reponer_stock_anulacion(integer, text) FROM PUBLIC;

-- T04) fn_anular_venta: misma lógica de 20261012_permisos_cajero.sql + reposición
CREATE OR REPLACE FUNCTION public.fn_anular_venta(p_venta_id INTEGER, p_motivo TEXT)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    actor_id INTEGER := public.fn_usuario_actual_id();
    actor_rol TEXT;
    venta public.ventas%ROWTYPE;
BEGIN
    IF actor_id IS NULL THEN
        RAISE EXCEPTION 'La sesión no identifica a un usuario autorizado' USING ERRCODE = '42501';
    END IF;
    SELECT rol INTO actor_rol FROM public.usuarios WHERE id = actor_id;
    IF p_motivo IS NULL OR length(btrim(p_motivo)) < 5 OR length(btrim(p_motivo)) > 250 THEN
        RAISE EXCEPTION 'El motivo debe tener entre 5 y 250 caracteres' USING ERRCODE = '22023';
    END IF;

    -- Bloquea la fila para impedir dos anulaciones concurrentes.
    SELECT * INTO venta FROM public.ventas WHERE id = p_venta_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La venta no existe o ya estaba anulada.' USING ERRCODE = '22023';
    END IF;
    IF actor_rol = 'cajero' AND venta.cajero_id IS DISTINCT FROM actor_id THEN
        RAISE EXCEPTION 'Solo puedes anular tus propias ventas' USING ERRCODE = '42501';
    END IF;
    IF venta.anulada THEN
        RAISE EXCEPTION 'La venta no existe o ya estaba anulada.' USING ERRCODE = '22023';
    END IF;

    UPDATE public.ventas
       SET anulada = TRUE, anulada_por = actor_id,
           anulada_en = clock_timestamp() AT TIME ZONE 'UTC', anulada_motivo = btrim(p_motivo)
     WHERE id = p_venta_id;

    -- H3.2 T08: devuelve al stock lo que descontó la venta (misma transacción).
    PERFORM public.fn_reponer_stock_anulacion(p_venta_id, p_motivo);

    RETURN p_venta_id;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_anular_venta(integer, text) FROM PUBLIC, web_anon, nury_bodeguero;
GRANT EXECUTE ON FUNCTION public.fn_anular_venta(integer, text) TO nury_admin, nury_cajero;

-- fn_anular_venta corre como su dueño y llama a la reposición: ese dueño debe poder ejecutarla.
DO $$
DECLARE
    v_owner TEXT;
BEGIN
    SELECT pg_get_userbyid(proowner) INTO v_owner
      FROM pg_proc WHERE oid = 'public.fn_anular_venta(integer,text)'::regprocedure;
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.fn_reponer_stock_anulacion(integer, text) TO %I', v_owner);
END $$;

COMMIT;


-- #####################################################################
-- 10. database/migrations/0007_venta_especial.sql
-- #####################################################################

-- H2.12 T05 — Venta a empleados: marca booleana de venta especial.
--
-- venta_especial = true  → venta a empleado, con descuento.
-- venta_especial = false → venta normal, sin descuento.
--
-- La calcula la base de datos a partir de tipo_venta (0004), así nunca
-- puede quedar distinta de ese valor. No se escribe desde el POS.

BEGIN;

ALTER TABLE public.ventas
    ADD COLUMN IF NOT EXISTS venta_especial BOOLEAN
        GENERATED ALWAYS AS (tipo_venta = 'empleado') STORED;

COMMENT ON COLUMN public.ventas.venta_especial IS
    'true si es venta a empleado (con descuento); false si es venta normal. Calculada desde tipo_venta.';

COMMIT;


-- #####################################################################
-- 11. database/migrations/0008_ajuste_stock_idempotente.sql
-- #####################################################################

-- H3.6 T06 - Reintentos de un ajuste de stock sin descuentos ni aumentos repetidos.
--
-- Problema: si la conexión se corta después de que fn_ajustar_stock aplicó el
-- ajuste pero antes de que llegue la respuesta, la pantalla no sabe si se aplicó.
-- Al reintentar, la base no tenía cómo reconocer la operación y la aplicaba otra vez.
--
-- Solución: la pantalla manda una clave (UUID) por operación y la repite en cada
-- reintento del mismo ajuste.
--   - Si la clave ya existe en el kardex, se devuelve ese movimiento sin tocar el stock.
--   - Si existe con otros datos (sucursal, ítem o cantidad), se rechaza.
--   - Un bloqueo por clave impide que dos reintentos simultáneos la apliquen dos veces;
--     además, un índice único lo impide en la base aunque alguien se salte la función.
--   - Sin clave (p_clave NULL) se comporta igual que antes.
-- Los ajustes simultáneos de un mismo ítem ya los ordena el FOR UPDATE de la fila de
-- stock: cada uno suma o resta sobre el stock que dejó el anterior.
--
-- Contenido:
--   T01  columna clave_idempotencia en movimientos_stock
--   T02  índice único de la clave
--   T03  fn_ajustar_stock con p_clave (reemplaza la de 0005_ajuste_stock.sql)
--
-- Requiere: 0005_ajuste_stock.sql.
--
-- ANTES DE APLICAR EN PRODUCCIÓN:
--   a) Confirmar que fn_ajustar_stock de producción es la de 0005 (T03 la reemplaza completa):
--        SELECT pg_get_functiondef('public.fn_ajustar_stock(integer,numeric,text,integer,integer)'::regprocedure);
--   b) Correr database/tests/ajuste_stock_idempotente.sql en una base de pruebas.
--   c) Después de aplicar: NOTIFY pgrst, 'reload schema';
--   d) Desplegar la pantalla que envía p_clave DESPUÉS de esta migración: la función
--      anterior no conoce p_clave y PostgREST rechazaría el ajuste (PGRST202).

BEGIN;

-- T01) Clave de la operación que originó el movimiento --------------------------
ALTER TABLE public.movimientos_stock
    ADD COLUMN IF NOT EXISTS clave_idempotencia UUID;

-- T02) Una clave, un solo movimiento -------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS ux_movimientos_clave_idempotencia
    ON public.movimientos_stock (clave_idempotencia)
    WHERE clave_idempotencia IS NOT NULL;

-- T03) fn_ajustar_stock con clave -----------------------------------------------
-- Se elimina la firma anterior: si convivieran las dos, PostgREST no sabría cuál llamar.
DROP FUNCTION IF EXISTS public.fn_ajustar_stock(integer, numeric, text, integer, integer);

CREATE FUNCTION public.fn_ajustar_stock(
    p_sucursal_id    INTEGER,
    p_cantidad       NUMERIC,
    p_motivo         TEXT,
    p_ingrediente_id INTEGER DEFAULT NULL,
    p_producto_id    INTEGER DEFAULT NULL,
    p_clave          UUID DEFAULT NULL
)
RETURNS public.movimientos_stock
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $function$
DECLARE
    v_motivo       TEXT := btrim(COALESCE(p_motivo, ''));
    v_stock_previo NUMERIC(12,3);
    v_nuevo_stock  NUMERIC(12,3);
    v_mov          public.movimientos_stock%ROWTYPE;
BEGIN
    -- Debe indicarse exactamente uno de los dos ítems.
    IF (p_ingrediente_id IS NULL) = (p_producto_id IS NULL) THEN
        RAISE EXCEPTION 'Indica un ingrediente o un producto (solo uno de los dos)'
            USING ERRCODE = '22023';
    END IF;

    -- Reintento de una operación ya registrada: se devuelve el mismo movimiento.
    IF p_clave IS NOT NULL THEN
        PERFORM pg_advisory_xact_lock(hashtextextended(p_clave::text, 0));

        SELECT * INTO v_mov
          FROM public.movimientos_stock
         WHERE clave_idempotencia = p_clave;

        IF FOUND THEN
            IF v_mov.tipo_movimiento <> 'ajuste'
               OR v_mov.sucursal_id <> p_sucursal_id
               OR v_mov.ingrediente_id IS DISTINCT FROM p_ingrediente_id
               OR v_mov.producto_id IS DISTINCT FROM p_producto_id
               OR v_mov.cantidad <> round(p_cantidad, 3) THEN
                RAISE EXCEPTION 'Este ajuste ya se registró con otros datos. Revisa el stock antes de registrar uno nuevo'
                    USING ERRCODE = '22023';
            END IF;
            RETURN v_mov;
        END IF;
    END IF;

    IF p_cantidad IS NULL OR p_cantidad = 0 THEN
        RAISE EXCEPTION 'La cantidad del ajuste es obligatoria y no puede ser 0'
            USING ERRCODE = '22023';
    END IF;

    IF v_motivo = '' THEN
        RAISE EXCEPTION 'El motivo del ajuste es obligatorio'
            USING ERRCODE = '22023';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.sucursales WHERE id = p_sucursal_id) THEN
        RAISE EXCEPTION 'La sucursal indicada no existe'
            USING ERRCODE = '23503';
    END IF;

    IF p_ingrediente_id IS NOT NULL THEN
        IF NOT EXISTS (SELECT 1 FROM public.ingredientes WHERE id = p_ingrediente_id) THEN
            RAISE EXCEPTION 'El ingrediente indicado no existe'
                USING ERRCODE = '23503';
        END IF;

        INSERT INTO public.stock_sucursal (ingrediente_id, sucursal_id, stock_actual, stock_minimo)
        VALUES (p_ingrediente_id, p_sucursal_id, 0, 0)
        ON CONFLICT (ingrediente_id, sucursal_id) DO NOTHING;

        SELECT stock_actual INTO v_stock_previo
          FROM public.stock_sucursal
         WHERE ingrediente_id = p_ingrediente_id AND sucursal_id = p_sucursal_id
         FOR UPDATE;
    ELSE
        IF NOT EXISTS (SELECT 1 FROM public.productos WHERE id = p_producto_id) THEN
            RAISE EXCEPTION 'El producto indicado no existe'
                USING ERRCODE = '23503';
        END IF;

        -- Un producto con receta no tiene stock propio: su stock son sus ingredientes.
        IF EXISTS (SELECT 1 FROM public.recetas WHERE producto_id = p_producto_id) THEN
            RAISE EXCEPTION 'Este producto tiene receta: su stock se ajusta a través de sus ingredientes'
                USING ERRCODE = '22023';
        END IF;

        INSERT INTO public.stock_producto_sucursal (producto_id, sucursal_id, stock_actual, stock_minimo)
        VALUES (p_producto_id, p_sucursal_id, 0, 0)
        ON CONFLICT (producto_id, sucursal_id) DO NOTHING;

        SELECT stock_actual INTO v_stock_previo
          FROM public.stock_producto_sucursal
         WHERE producto_id = p_producto_id AND sucursal_id = p_sucursal_id
         FOR UPDATE;
    END IF;

    v_nuevo_stock := v_stock_previo + p_cantidad;

    -- Un ajuste de salida no puede dejar el stock en negativo. Una entrada sí se
    -- permite aunque el stock siga negativo (p. ej. para regularizar ventas de prueba).
    IF p_cantidad < 0 AND v_nuevo_stock < 0 THEN
        RAISE EXCEPTION 'El ajuste dejaría el stock en negativo (actual: %, ajuste: %)',
            v_stock_previo, p_cantidad
            USING ERRCODE = '23514';
    END IF;

    IF p_ingrediente_id IS NOT NULL THEN
        UPDATE public.stock_sucursal
           SET stock_actual = v_nuevo_stock, actualizado_en = now()
         WHERE ingrediente_id = p_ingrediente_id AND sucursal_id = p_sucursal_id;
    ELSE
        UPDATE public.stock_producto_sucursal
           SET stock_actual = v_nuevo_stock, actualizado_en = now()
         WHERE producto_id = p_producto_id AND sucursal_id = p_sucursal_id;
    END IF;

    INSERT INTO public.movimientos_stock
        (ingrediente_id, producto_id, sucursal_id, tipo_movimiento, cantidad,
         stock_resultante, referencia_tipo, nota, clave_idempotencia)
    VALUES
        (p_ingrediente_id, p_producto_id, p_sucursal_id, 'ajuste', p_cantidad,
         v_nuevo_stock, 'ajuste_manual', v_motivo, p_clave)
    RETURNING * INTO v_mov;

    RETURN v_mov;
END;
$function$;

-- Solo roles de inventario. PostgREST publica únicamente lo ejecutable por el rol de la sesión.
REVOKE ALL ON FUNCTION public.fn_ajustar_stock(integer, numeric, text, integer, integer, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_ajustar_stock(integer, numeric, text, integer, integer, uuid)
    TO nury_admin, nury_bodeguero;

COMMIT;


-- #####################################################################
-- 12. database/migrations/20260928_crear_usuario_rpc.sql
-- #####################################################################

-- Alta de usuarios desde la aplicación. El hash se genera en PostgreSQL;
-- el RPC nunca retorna password_hash.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

ALTER TABLE usuarios
    DROP CONSTRAINT IF EXISTS usuarios_rol_check;

ALTER TABLE usuarios
    ADD CONSTRAINT usuarios_rol_check
    CHECK (rol IN ('admin', 'administrador', 'cajero', 'bodeguero'));

CREATE OR REPLACE FUNCTION crear_usuario(
    p_nombre VARCHAR(120),
    p_identificador_acceso VARCHAR(120),
    p_contrasena TEXT,
    p_rol VARCHAR(20),
    p_sucursal_id INTEGER,
    p_debe_cambiar_password BOOLEAN,
    p_activo BOOLEAN
)
RETURNS TABLE (
    id INTEGER,
    nombre VARCHAR(120),
    identificador_acceso VARCHAR(120),
    rol VARCHAR(20),
    sucursal_id INTEGER,
    debe_cambiar_password BOOLEAN,
    activo BOOLEAN,
    creado_en TIMESTAMP,
    actualizado_en TIMESTAMP
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_nombre IS NULL OR btrim(p_nombre) = '' THEN
        RAISE EXCEPTION 'El nombre es obligatorio';
    END IF;

    IF p_identificador_acceso IS NULL OR btrim(p_identificador_acceso) = '' THEN
        RAISE EXCEPTION 'El usuario de acceso es obligatorio';
    END IF;

    IF p_contrasena IS NULL OR length(p_contrasena) < 4 THEN
        RAISE EXCEPTION 'La contraseña debe tener al menos 4 caracteres';
    END IF;

    RETURN QUERY
    INSERT INTO usuarios AS u (
        nombre,
        identificador_acceso,
        password_hash,
        rol,
        sucursal_id,
        debe_cambiar_password,
        activo
    )
    VALUES (
        p_nombre,
        p_identificador_acceso,
        crypt(p_contrasena, gen_salt('bf')),
        p_rol,
        p_sucursal_id,
        p_debe_cambiar_password,
        p_activo
    )
    RETURNING u.id, u.nombre, u.identificador_acceso, u.rol, u.sucursal_id,
              u.debe_cambiar_password, u.activo, u.creado_en, u.actualizado_en;
END;
$$;

-- PostgREST solo publica las funciones ejecutables por el rol de la sesión.
REVOKE ALL ON FUNCTION public.crear_usuario(
    character varying,
    character varying,
    text,
    character varying,
    integer,
    boolean,
    boolean
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.crear_usuario(
    character varying,
    character varying,
    text,
    character varying,
    integer,
    boolean,
    boolean
) TO nury_admin;

-- Refresca el caché de funciones de PostgREST después de aplicar la migración.
NOTIFY pgrst, 'reload schema';


-- #####################################################################
-- 13. database/migrations/20260928_roles_usuarios.sql
-- #####################################################################

-- Alinea los roles aceptados por usuarios con los roles que usa la aplicación.
-- La edición del esquema base cubre instalaciones nuevas; esta migración
-- actualiza bases de datos que ya fueron inicializadas.
ALTER TABLE usuarios
    DROP CONSTRAINT IF EXISTS usuarios_rol_check;

ALTER TABLE usuarios
    ADD CONSTRAINT usuarios_rol_check
    CHECK (rol IN ('admin', 'administrador', 'cajero', 'bodeguero'));


-- #####################################################################
-- 14. database/migrations/20260930_sucursales_api.sql
-- #####################################################################

-- Requiere los roles JWT existentes: nury_admin, nury_cajero,
-- nury_bodeguero y web_anon. No altera las sucursales registradas.
BEGIN;

ALTER TABLE public.sucursales
    DROP CONSTRAINT IF EXISTS sucursales_nombre_no_vacio;
ALTER TABLE public.sucursales
    ADD CONSTRAINT sucursales_nombre_no_vacio CHECK (btrim(nombre) <> '');

CREATE OR REPLACE FUNCTION public.fn_normalizar_sucursal()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    NEW.nombre := btrim(NEW.nombre);
    NEW.direccion := NULLIF(btrim(NEW.direccion), '');
    NEW.telefono := NULLIF(btrim(NEW.telefono), '');
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_normalizar_sucursal ON public.sucursales;
CREATE TRIGGER trg_normalizar_sucursal
BEFORE INSERT OR UPDATE OF nombre, direccion, telefono ON public.sucursales
FOR EACH ROW EXECUTE FUNCTION public.fn_normalizar_sucursal();

CREATE OR REPLACE FUNCTION public.crear_sucursal(
    p_nombre VARCHAR(120),
    p_direccion VARCHAR(200) DEFAULT NULL,
    p_telefono VARCHAR(30) DEFAULT NULL,
    p_activo BOOLEAN DEFAULT TRUE
)
RETURNS TABLE (
    id INTEGER,
    nombre VARCHAR(120),
    direccion VARCHAR(200),
    telefono VARCHAR(30),
    activo BOOLEAN,
    creado_en TIMESTAMP
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
BEGIN
    RETURN QUERY
    INSERT INTO public.sucursales AS s (nombre, direccion, telefono, activo)
    VALUES (p_nombre, p_direccion, p_telefono, p_activo)
    RETURNING s.id, s.nombre, s.direccion, s.telefono, s.activo, s.creado_en;
END;
$$;

-- Solo el administrador puede dar de alta o editar sucursales.
-- Se conservan los permisos de lectura existentes de cajero y bodeguero.
REVOKE INSERT, UPDATE ON public.sucursales
    FROM PUBLIC, web_anon, nury_cajero, nury_bodeguero, nury_admin;
GRANT USAGE ON SCHEMA public TO nury_admin;
GRANT SELECT ON public.sucursales TO nury_admin;
GRANT INSERT (nombre, direccion, telefono, activo),
      UPDATE (nombre, direccion, telefono, activo)
    ON public.sucursales TO nury_admin;
GRANT USAGE ON SEQUENCE public.sucursales_id_seq TO nury_admin;

REVOKE ALL ON FUNCTION public.crear_sucursal(
    character varying, character varying, character varying, boolean
) FROM PUBLIC, web_anon, nury_cajero, nury_bodeguero;
GRANT EXECUTE ON FUNCTION public.crear_sucursal(
    character varying, character varying, character varying, boolean
) TO nury_admin;

NOTIFY pgrst, 'reload schema';
COMMIT;


-- #####################################################################
-- 15. database/migrations/20261012_permisos_cajero.sql
-- #####################################################################

-- Requiere los roles JWT nury_admin, nury_cajero, nury_bodeguero y web_anon.
-- El JWT de login debe identificar al usuario con user_id, usuario_id, sub o id.
-- Aplicar con el propietario de las tablas. No modifica ventas ni productos existentes.
BEGIN;

-- El Maestro ya usa este campo; algunos esquemas iniciales todavía no lo incluyen.
ALTER TABLE public.productos ADD COLUMN IF NOT EXISTS precio_compra NUMERIC(12,2);

CREATE OR REPLACE FUNCTION public.fn_usuario_actual_id()
RETURNS INTEGER
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    WITH sesion AS (
        SELECT COALESCE(NULLIF(current_setting('request.jwt.claims', TRUE), ''), '{}')::jsonb AS claims
    ), identidad AS (
        SELECT claims->>'role' AS rol,
               COALESCE(claims->>'user_id', claims->>'usuario_id', claims->>'sub', claims->>'id') AS id
          FROM sesion
    )
    SELECT u.id
      FROM public.usuarios u, identidad i
     WHERE u.id = CASE WHEN i.id ~ '^[0-9]{1,10}$' THEN i.id::bigint ELSE NULL END
       AND u.activo
       AND CASE WHEN u.rol IN ('admin', 'administrador') THEN 'nury_admin'
                WHEN u.rol = 'cajero' THEN 'nury_cajero' END = i.rol;
$$;

REVOKE ALL ON FUNCTION public.fn_usuario_actual_id() FROM PUBLIC, web_anon, nury_bodeguero;
GRANT EXECUTE ON FUNCTION public.fn_usuario_actual_id() TO nury_admin, nury_cajero;

-- El historial y su detalle quedan limitados al cajero autenticado.
ALTER TABLE public.ventas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.detalle_venta ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS ventas_admin ON public.ventas;
CREATE POLICY ventas_admin ON public.ventas TO nury_admin USING (TRUE) WITH CHECK (TRUE);
DROP POLICY IF EXISTS ventas_cajero_lectura ON public.ventas;
CREATE POLICY ventas_cajero_lectura ON public.ventas FOR SELECT TO nury_cajero
    USING (cajero_id = (SELECT public.fn_usuario_actual_id()));
DROP POLICY IF EXISTS ventas_cajero_limite ON public.ventas;
CREATE POLICY ventas_cajero_limite ON public.ventas AS RESTRICTIVE FOR SELECT TO nury_cajero
    USING (cajero_id = (SELECT public.fn_usuario_actual_id()));

DROP POLICY IF EXISTS detalle_venta_admin ON public.detalle_venta;
CREATE POLICY detalle_venta_admin ON public.detalle_venta TO nury_admin USING (TRUE) WITH CHECK (TRUE);
DROP POLICY IF EXISTS detalle_venta_cajero_lectura ON public.detalle_venta;
CREATE POLICY detalle_venta_cajero_lectura ON public.detalle_venta FOR SELECT TO nury_cajero
    USING (EXISTS (SELECT 1 FROM public.ventas v WHERE v.id = venta_id));
DROP POLICY IF EXISTS detalle_venta_cajero_limite ON public.detalle_venta;
CREATE POLICY detalle_venta_cajero_limite ON public.detalle_venta AS RESTRICTIVE FOR SELECT TO nury_cajero
    USING (EXISTS (SELECT 1 FROM public.ventas v WHERE v.id = venta_id));

GRANT USAGE ON SCHEMA public TO nury_admin, nury_cajero;
GRANT SELECT ON public.ventas, public.detalle_venta, public.productos TO nury_admin, nury_cajero;
REVOKE INSERT, UPDATE, DELETE ON public.ventas, public.detalle_venta FROM PUBLIC, web_anon, nury_cajero;
REVOKE INSERT, UPDATE, DELETE ON public.productos FROM PUBLIC, web_anon, nury_cajero;

-- También elimina grants por columna de versiones anteriores de la API.
DO $$
DECLARE
    tabla TEXT;
    columnas TEXT;
BEGIN
    FOREACH tabla IN ARRAY ARRAY['ventas', 'detalle_venta', 'productos'] LOOP
        SELECT string_agg(quote_ident(column_name), ', ')
          INTO columnas FROM information_schema.columns
         WHERE table_schema = 'public' AND table_name = tabla;
        EXECUTE format('REVOKE INSERT (%s), UPDATE (%s) ON public.%I FROM PUBLIC, web_anon, nury_cajero',
                       columnas, columnas, tabla);
    END LOOP;
END;
$$;

-- El cajero mantiene alta y edición de datos, sin eliminar ni cambiar activo.
GRANT INSERT (nombre, categoria, precio_compra, precio_venta, codigo_barras),
      UPDATE (nombre, categoria, precio_compra, precio_venta, codigo_barras)
    ON public.productos TO nury_cajero;
GRANT USAGE ON SEQUENCE public.productos_id_seq TO nury_cajero;

CREATE OR REPLACE FUNCTION public.fn_anular_venta(p_venta_id INTEGER, p_motivo TEXT)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    actor_id INTEGER := public.fn_usuario_actual_id();
    actor_rol TEXT;
    venta public.ventas%ROWTYPE;
BEGIN
    IF actor_id IS NULL THEN
        RAISE EXCEPTION 'La sesión no identifica a un usuario autorizado' USING ERRCODE = '42501';
    END IF;
    SELECT rol INTO actor_rol FROM public.usuarios WHERE id = actor_id;
    IF p_motivo IS NULL OR length(btrim(p_motivo)) < 5 OR length(btrim(p_motivo)) > 250 THEN
        RAISE EXCEPTION 'El motivo debe tener entre 5 y 250 caracteres' USING ERRCODE = '22023';
    END IF;

    -- Bloquea la fila para impedir dos anulaciones concurrentes.
    SELECT * INTO venta FROM public.ventas WHERE id = p_venta_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La venta no existe o ya estaba anulada.' USING ERRCODE = '22023';
    END IF;
    IF actor_rol = 'cajero' AND venta.cajero_id IS DISTINCT FROM actor_id THEN
        RAISE EXCEPTION 'Solo puedes anular tus propias ventas' USING ERRCODE = '42501';
    END IF;
    IF venta.anulada THEN
        RAISE EXCEPTION 'La venta no existe o ya estaba anulada.' USING ERRCODE = '22023';
    END IF;

    UPDATE public.ventas
       SET anulada = TRUE, anulada_por = actor_id,
           anulada_en = clock_timestamp() AT TIME ZONE 'UTC', anulada_motivo = btrim(p_motivo)
     WHERE id = p_venta_id;
    RETURN p_venta_id;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_anular_venta(integer, text) FROM PUBLIC, web_anon, nury_bodeguero;
GRANT EXECUTE ON FUNCTION public.fn_anular_venta(integer, text) TO nury_admin, nury_cajero;

NOTIFY pgrst, 'reload schema';
COMMIT;


-- #####################################################################
-- 16. database/migrations/20261012_recuperar_turno.sql
-- #####################################################################

-- Requiere 0003_apertura_control_turno.sql y 20261012_permisos_cajero.sql.
-- Recupera un turno existente. No abre, cierra ni modifica turnos o ventas.
BEGIN;

DO $$
BEGIN
    IF to_regprocedure('public.fn_usuario_actual_id()') IS NULL THEN
        RAISE EXCEPTION 'Aplica primero 20261012_permisos_cajero.sql';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_recuperar_turno()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
    actor_id INTEGER := public.fn_usuario_actual_id();
    sucursal INTEGER;
    turno public.turnos%ROWTYPE;
    ventas JSONB;
BEGIN
    IF actor_id IS NULL THEN
        RAISE EXCEPTION 'La sesión no identifica a un usuario autorizado' USING ERRCODE = '42501';
    END IF;
    SELECT sucursal_id INTO sucursal FROM public.usuarios WHERE id = actor_id;
    SELECT * INTO turno FROM public.turnos
     WHERE usuario_id = actor_id AND sucursal_id = sucursal AND hora_fin IS NULL
     ORDER BY hora_inicio DESC, id DESC LIMIT 1;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('turno', NULL, 'ventas', '[]'::jsonb);
    END IF;

    SELECT COALESCE(jsonb_agg(to_jsonb(v) || jsonb_build_object('detalle_venta', (
        SELECT COALESCE(jsonb_agg(to_jsonb(d) || jsonb_build_object('productos', to_jsonb(p)) ORDER BY d.id), '[]'::jsonb)
          FROM public.detalle_venta d
          LEFT JOIN public.productos p ON p.id = d.producto_id
         WHERE d.venta_id = v.id
    )) ORDER BY v.fecha_venta DESC, v.id DESC), '[]'::jsonb)
      INTO ventas FROM public.ventas v
     WHERE v.turno_id = turno.id AND v.cajero_id = actor_id AND v.sucursal_id = sucursal;

    RETURN jsonb_build_object('turno', to_jsonb(turno), 'ventas', ventas);
END;
$$;

REVOKE ALL ON FUNCTION public.fn_recuperar_turno() FROM PUBLIC, web_anon, nury_bodeguero;
GRANT EXECUTE ON FUNCTION public.fn_recuperar_turno() TO nury_admin, nury_cajero;
NOTIFY pgrst, 'reload schema';
COMMIT;


-- #####################################################################
-- 17. database/migrations/20261016_facturas_xml_pendientes.sql
-- #####################################################################

-- Facturas XML sin confirmar (H3.1 T02 + H3.7 T02).
--
-- Contexto: una factura XML cargada pero no confirmada debe guardarse en una
-- tabla propia. Si sus líneas se insertaran en detalle_factura_compra, el
-- trigger fn_aplicar_compra (AFTER INSERT) sumaría stock antes de confirmar.
-- Por eso la carga guarda aquí, y solo al confirmar (H3.1 T08) se crean
-- facturas_compra y detalle_factura_compra en una sola transacción.
--
-- Este script solo CREA tablas nuevas. No modifica facturas_compra ni
-- detalle_factura_compra y no toca stock.
--
-- ANTES DE APLICAR EN PRODUCCIÓN:
--   a) Revisar el script completo con el responsable.
--   b) Correr primero 20261016_facturas_xml_pendientes.ENSAYO.sql (termina en ROLLBACK).
--   c) Después de aplicar: NOTIFY pgrst, 'reload schema';

BEGIN;

-- Cabecera de la factura XML pendiente ----------------------------------------

CREATE TABLE IF NOT EXISTS public.facturas_xml_pendientes (
    id                      SERIAL PRIMARY KEY,
    sucursal_id             INTEGER NOT NULL REFERENCES public.sucursales(id),
    cargado_por             INTEGER NOT NULL REFERENCES public.usuarios(id),
    estado                  VARCHAR(20) NOT NULL DEFAULT 'pendiente'
                                CHECK (estado IN ('pendiente','confirmada','cancelada')),

    -- Identidad del documento tal como viene en el XML.
    tipo_documento          SMALLINT NOT NULL CHECK (tipo_documento = 33),  -- solo factura electrónica
    folio                   BIGINT NOT NULL CHECK (folio > 0),
    rut_emisor              VARCHAR(12) NOT NULL,                             -- ej. '82623500-4'
    rut_emisor_normalizado  VARCHAR(12) NOT NULL,                             -- sin puntos, guion en su sitio, DV en mayúscula (lo calcula la carga)

    -- Datos informativos. El RUT receptor NO se valida (decisión 16/10/2026).
    razon_social_emisor     VARCHAR(150),
    rut_receptor            VARCHAR(12),
    fecha_emision           DATE NOT NULL,
    fecha_vencimiento       DATE,
    forma_pago              SMALLINT,
    orden_compra_referencia VARCHAR(60),                                     -- folio de la referencia tipo 801, si viene

    -- Totales tal como vienen en el XML.
    monto_neto              NUMERIC(12,2) NOT NULL,
    monto_iva               NUMERIC(12,2) NOT NULL,
    tasa_iva                NUMERIC(5,2),
    monto_total             NUMERIC(12,2) NOT NULL,

    -- Respaldo del archivo original.
    xml_original            BYTEA NOT NULL,                                  -- bytes tal cual llegaron
    xml_nombre              VARCHAR(255),
    xml_sha256              CHAR(64) NOT NULL,                               -- para detectar archivo repetido (H3.7)
    detalle_incluye_iva     BOOLEAN NOT NULL DEFAULT FALSE,                  -- sin IndMntNeto: se asume neto (supuesto registrado)

    -- Al confirmar (H3.1 T08).
    factura_id              INTEGER REFERENCES public.facturas_compra(id),
    confirmado_por          INTEGER REFERENCES public.usuarios(id),
    confirmado_en           TIMESTAMP,

    creado_en               TIMESTAMP NOT NULL DEFAULT now(),
    CHECK ((estado = 'confirmada') = (factura_id IS NOT NULL))
);

CREATE INDEX IF NOT EXISTS idx_facturas_xml_pendientes_identidad
    ON public.facturas_xml_pendientes(rut_emisor_normalizado, tipo_documento, folio);

CREATE INDEX IF NOT EXISTS idx_facturas_xml_pendientes_sucursal
    ON public.facturas_xml_pendientes(sucursal_id, estado);

-- Líneas del XML, con su asociación al catálogo (H3.1 T05/T06) -----------------

CREATE TABLE IF NOT EXISTS public.facturas_xml_pendientes_lineas (
    id                          SERIAL PRIMARY KEY,
    factura_xml_id              INTEGER NOT NULL REFERENCES public.facturas_xml_pendientes(id) ON DELETE CASCADE,
    numero_linea                INTEGER NOT NULL CHECK (numero_linea > 0),     -- NroLinDet

    -- Datos tal como vienen en el XML.
    codigo_tipo                 VARCHAR(20),                                   -- TpoCodigo (viene vacío en el ejemplo)
    codigo_proveedor            VARCHAR(60),                                   -- VlrCodigo
    descripcion                 VARCHAR(255) NOT NULL,                         -- NmbItem (puede traer el código pegado)
    cantidad                    NUMERIC(12,3) NOT NULL CHECK (cantidad > 0),   -- QtyItem, en unidad de compra
    precio_unitario             NUMERIC(14,4) NOT NULL CHECK (precio_unitario >= 0),  -- PrcItem
    monto                       NUMERIC(12,2) NOT NULL,                        -- MontoItem

    -- Asociación con el catálogo. Se completa en H3.1 T05/T06; queda NULL hasta entonces.
    ingrediente_id              INTEGER REFERENCES public.ingredientes(id),
    producto_id                 INTEGER REFERENCES public.productos(id),
    no_corresponde_inventario   BOOLEAN NOT NULL DEFAULT FALSE,                -- servicios, etc.

    UNIQUE (factura_xml_id, numero_linea),
    CHECK (num_nonnulls(ingrediente_id, producto_id) <= 1),
    CHECK (NOT (no_corresponde_inventario AND num_nonnulls(ingrediente_id, producto_id) > 0))
);

-- Mismo dueño y permisos que las tablas de factura existentes -----------------
-- (se copian de facturas_compra; revisar antes de aplicar).

DO $$
DECLARE
    v_owner TEXT;
    r       RECORD;
    t       TEXT;
BEGIN
    SELECT pg_get_userbyid(relowner) INTO v_owner
      FROM pg_class WHERE oid = 'public.facturas_compra'::regclass;

    FOREACH t IN ARRAY ARRAY['facturas_xml_pendientes', 'facturas_xml_pendientes_lineas'] LOOP
        EXECUTE format('ALTER TABLE public.%I OWNER TO %I', t, v_owner);
        EXECUTE format('ALTER SEQUENCE public.%I OWNER TO %I', t || '_id_seq', v_owner);

        FOR r IN
            SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(a.grantee)) END AS grantee,
                   a.privilege_type
              FROM pg_class c, LATERAL aclexplode(c.relacl) a
             WHERE c.oid = 'public.facturas_compra'::regclass
               AND a.grantee <> c.relowner
        LOOP
            EXECUTE format('GRANT %s ON public.%I TO %s', r.privilege_type, t, r.grantee);
        END LOOP;
    END LOOP;
END $$;

COMMIT;


-- #####################################################################
-- 18. database/migrations/20261017_equivalencias_lineas_xml.sql
-- #####################################################################

-- Equivalencias y cantidad a ingresar en las líneas de facturas XML (H3.1 T06).
--
-- Cada línea del XML trae la cantidad en la unidad de compra (bolsas, cajas…).
-- Antes de sumar stock, el usuario confirma cuántas unidades del catálogo trae
-- cada presentación (nunca se deduce del nombre). La base calcula la cantidad a
-- ingresar, separada de la cantidad original del XML.
--
--   cantidad                   QtyItem del XML, tal como vino (ya existía).
--   unidades_por_presentacion  equivalencia confirmada por el usuario. NULL = falta confirmarla.
--   cantidad_ingreso           cantidad × unidades_por_presentacion, en la unidad del catálogo
--                              (unidad del ingrediente, o unidades si es producto).
--
-- Reglas que la base exige (validación en servidor):
--   - la equivalencia, si está, es mayor que cero;
--   - solo hay equivalencia en líneas asociadas a una materia prima o a un producto
--     (no en líneas pendientes ni «No corresponde a inventario»).
-- Que todas las líneas inventariables tengan equivalencia antes de confirmar se
-- comprueba en la función de confirmación (H3.1 T08).
--
-- REQUIERE: 20261016_facturas_xml_pendientes.sql aplicado antes.
--
-- ANTES DE APLICAR EN PRODUCCIÓN:
--   a) Revisar el script completo con el responsable.
--   b) Correr primero 20261017_equivalencias_lineas_xml.ENSAYO.sql (termina en ROLLBACK).
--   c) Después de aplicar: NOTIFY pgrst, 'reload schema';

BEGIN;

ALTER TABLE public.facturas_xml_pendientes_lineas
    ADD COLUMN IF NOT EXISTS unidades_por_presentacion NUMERIC(12,3);

ALTER TABLE public.facturas_xml_pendientes_lineas
    ADD COLUMN IF NOT EXISTS cantidad_ingreso NUMERIC(14,3)
        GENERATED ALWAYS AS (cantidad * unidades_por_presentacion) STORED;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conrelid = 'public.facturas_xml_pendientes_lineas'::regclass
                      AND conname = 'facturas_xml_lineas_equivalencia_positiva') THEN
        ALTER TABLE public.facturas_xml_pendientes_lineas
            ADD CONSTRAINT facturas_xml_lineas_equivalencia_positiva
            CHECK (unidades_por_presentacion IS NULL OR unidades_por_presentacion > 0);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conrelid = 'public.facturas_xml_pendientes_lineas'::regclass
                      AND conname = 'facturas_xml_lineas_equivalencia_con_articulo') THEN
        ALTER TABLE public.facturas_xml_pendientes_lineas
            ADD CONSTRAINT facturas_xml_lineas_equivalencia_con_articulo
            CHECK (unidades_por_presentacion IS NULL
                   OR num_nonnulls(ingrediente_id, producto_id) = 1);
    END IF;
END $$;

COMMIT;


-- #####################################################################
-- 19. database/migrations/20261017_ingresar_factura_xml.sql
-- #####################################################################

-- Confirmación transaccional del ingreso de una factura XML (H3.1 T08) e
-- identidad única de la factura (H3.7 T02).
--
-- La pantalla envía el archivo XML tal cual llegó, la sucursal y qué hacer con cada
-- línea (artículo y equivalencia, o «No corresponde a inventario»). El servidor:
--   1. Valida el permiso y la sucursal (fn_validar_sucursal_ingreso, H3.1 T07).
--   2. Vuelve a leer el XML: no confía en los datos que calculó el navegador.
--      Tipo 33, folio, fecha, RUT emisor, totales y cada línea se validan aquí.
--   3. Rechaza la factura si ya fue ingresada (RUT emisor normalizado + tipo + folio),
--      aunque cambie el nombre del archivo o la sucursal.
--   4. Exige que cada línea tenga artículo y equivalencia, o esté marcada como no
--      inventariable.
--   5. En una sola transacción: crea facturas_compra, la factura y sus líneas en las
--      tablas de pendientes (como respaldo, con el XML original) y el detalle de compra.
--      El stock lo suma fn_aplicar_compra, una vez por línea de detalle.
--   Si algo falla, no queda nada guardado: ni factura, ni líneas, ni stock.
--
-- Costo (decidido el 17/10/2026): costo por unidad = monto neto de la línea ÷ cantidad
-- a ingresar, sin IVA. Si la factura indica IndMntBruto = 1, se descuenta el IVA.
-- precio_unitario solo admite 2 decimales: la diferencia de redondeo se deja en
-- descuento_monto (puede ser negativa) para que subtotal_neto sea exactamente el monto
-- de la línea del XML.
--
-- Facturas ingresadas a mano (sin RUT, tipo y folio) quedan fuera de la restricción
-- única (decidido el 17/10/2026): la restricción trata los NULL como distintos.
--
-- REQUIERE (aplicados antes): 20261016_facturas_xml_pendientes.sql,
-- 20261017_equivalencias_lineas_xml.sql y 20261017_permisos_ingreso_facturas.sql.
--
-- ANTES DE APLICAR EN PRODUCCIÓN:
--   a) Revisar el script completo con el responsable.
--   b) Correr primero 20261017_ingresar_factura_xml.ENSAYO.sql (termina en ROLLBACK).
--   c) Después de aplicar: NOTIFY pgrst, 'reload schema';

BEGIN;

-- 1) Identidad de la factura en facturas_compra (H3.7 T02) ------------------------

ALTER TABLE public.facturas_compra
    ADD COLUMN IF NOT EXISTS origen                 VARCHAR(10) NOT NULL DEFAULT 'manual',
    ADD COLUMN IF NOT EXISTS rut_emisor_normalizado VARCHAR(12),
    ADD COLUMN IF NOT EXISTS tipo_documento         SMALLINT,
    ADD COLUMN IF NOT EXISTS folio                  BIGINT;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conrelid = 'public.facturas_compra'::regclass
                      AND conname = 'facturas_compra_origen_check') THEN
        ALTER TABLE public.facturas_compra
            ADD CONSTRAINT facturas_compra_origen_check CHECK (origen IN ('manual', 'xml'));
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conrelid = 'public.facturas_compra'::regclass
                      AND conname = 'facturas_compra_identidad_xml') THEN
        -- Toda factura que entra por XML trae su identidad completa.
        ALTER TABLE public.facturas_compra
            ADD CONSTRAINT facturas_compra_identidad_xml
            CHECK (origen <> 'xml'
                   OR (rut_emisor_normalizado IS NOT NULL AND tipo_documento IS NOT NULL AND folio IS NOT NULL));
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conrelid = 'public.facturas_compra'::regclass
                      AND conname = 'facturas_compra_identidad_unica') THEN
        ALTER TABLE public.facturas_compra
            ADD CONSTRAINT facturas_compra_identidad_unica
            UNIQUE (rut_emisor_normalizado, tipo_documento, folio);
    END IF;
END $$;

-- 2) RUT normalizado: 12345678-K, con el dígito verificador comprobado -------------

CREATE OR REPLACE FUNCTION public.fn_normalizar_rut(p_rut TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_partes  TEXT[];
    v_cuerpo  TEXT;
    v_dv      TEXT;
    v_suma    INTEGER := 0;
    v_factor  INTEGER := 2;
    v_resto   INTEGER;
    v_pos     INTEGER;
BEGIN
    v_partes := regexp_match(upper(regexp_replace(COALESCE(p_rut, ''), '[.\s]', '', 'g')),
                             '^0*([0-9]{1,8})-?([0-9K])$');
    IF v_partes IS NULL THEN
        RETURN NULL;
    END IF;
    v_cuerpo := v_partes[1];
    v_dv := v_partes[2];

    FOR v_pos IN REVERSE length(v_cuerpo)..1 LOOP
        v_suma := v_suma + substr(v_cuerpo, v_pos, 1)::INTEGER * v_factor;
        v_factor := CASE WHEN v_factor = 7 THEN 2 ELSE v_factor + 1 END;
    END LOOP;
    v_resto := 11 - (v_suma % 11);

    IF (CASE v_resto WHEN 11 THEN '0' WHEN 10 THEN 'K' ELSE v_resto::TEXT END) <> v_dv THEN
        RETURN NULL;
    END IF;
    RETURN v_cuerpo || '-' || v_dv;
END;
$$;

-- 3) Lectura de un valor del DTE sin depender del namespace ------------------------
-- p_ruta es relativa al Documento ('Encabezado/IdDoc/Folio'), o a su línea número
-- p_detalle ('NmbItem'). Devuelve el texto sin espacios en los extremos, o NULL.

CREATE OR REPLACE FUNCTION public.fn_dte_texto(p_doc XML, p_ruta TEXT, p_detalle INTEGER DEFAULT NULL)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_xpath TEXT := '//*[local-name()="Documento"]';
    v_parte TEXT;
    v_valor TEXT;
BEGIN
    IF p_detalle IS NOT NULL THEN
        v_xpath := '(' || v_xpath || '/*[local-name()="Detalle"])[' || p_detalle || ']';
    END IF;
    FOREACH v_parte IN ARRAY string_to_array(p_ruta, '/') LOOP
        v_xpath := v_xpath || '/*[local-name()="' || v_parte || '"]';
    END LOOP;

    v_valor := (xpath('string(' || v_xpath || '[1])', p_doc))[1]::TEXT;
    -- xpath() devuelve el texto como XML: se deshacen las entidades básicas.
    v_valor := replace(replace(replace(replace(replace(v_valor,
                   '&lt;', '<'), '&gt;', '>'), '&quot;', '"'), '&apos;', ''''), '&amp;', '&');
    RETURN NULLIF(btrim(v_valor), '');
END;
$$;

-- 4) Ingreso completo de la factura ---------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_ingresar_factura_xml(
    p_sucursal_id INTEGER,
    p_xml_base64  TEXT,
    p_xml_nombre  TEXT,
    p_lineas      JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    c_documento CONSTANT TEXT := '//*[local-name()="Documento"]';
    c_tamano_maximo CONSTANT INTEGER := 5 * 1024 * 1024;

    v_actor            INTEGER;
    v_bytes            BYTEA;
    v_contenido        BYTEA;
    v_codificacion     TEXT;
    v_texto            TEXT;
    v_doc              XML;
    v_cantidad_docs    INTEGER;

    v_tipo             TEXT;
    v_folio_txt        TEXT;
    v_folio            BIGINT;
    v_fecha_txt        TEXT;
    v_fecha            DATE;
    v_venc_txt         TEXT;
    v_venc             DATE;
    v_rut              TEXT;
    v_rut_norm         TEXT;
    v_neto             NUMERIC;
    v_exento           NUMERIC;
    v_iva              NUMERIC;
    v_total            NUMERIC;
    v_tasa             NUMERIC;
    v_otros_txt        TEXT;
    v_otros            NUMERIC;
    v_incluye_iva      BOOLEAN;
    v_forma_pago       TEXT;
    v_orden_compra     TEXT;

    v_existente        INTEGER;
    v_proveedor        INTEGER;
    v_factura          INTEGER;
    v_pendiente        INTEGER;

    v_total_lineas     INTEGER;
    v_numeros          INTEGER[] := '{}';
    v_pos              INTEGER;
    v_nro              INTEGER;
    v_nro_txt          TEXT;
    v_desc             TEXT;
    v_codigo           TEXT;
    v_codigo_tipo      TEXT;
    v_qty_txt          TEXT;
    v_qty              NUMERIC;
    v_prc_txt          TEXT;
    v_prc              NUMERIC;
    v_monto_txt        TEXT;
    v_monto            NUMERIC;

    v_cuenta           INTEGER;
    v_asoc             JSONB;
    v_ingrediente      INTEGER;
    v_producto         INTEGER;
    v_no_inventario    BOOLEAN;
    v_equivalencia     NUMERIC;
    v_unidad           INTEGER;
    v_cantidad         NUMERIC;
    v_costo            NUMERIC;
    v_precio           NUMERIC;

    v_sin_asociar      INTEGER := 0;
    v_sin_equivalencia INTEGER := 0;
    v_lineas_stock     INTEGER := 0;
    v_lineas_otras     INTEGER := 0;
BEGIN
    -- Permiso y sucursal (42501 si no corresponde).
    v_actor := public.fn_validar_sucursal_ingreso(p_sucursal_id);

    IF p_lineas IS NULL OR jsonb_typeof(p_lineas) <> 'array' THEN
        RAISE EXCEPTION 'Indica qué hacer con cada línea de la factura' USING ERRCODE = '22023';
    END IF;

    -- Archivo ------------------------------------------------------------------
    BEGIN
        v_bytes := decode(COALESCE(p_xml_base64, ''), 'base64');
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'El archivo no llegó completo. Vuelve a elegirlo.' USING ERRCODE = '22023';
    END;
    IF length(v_bytes) = 0 THEN
        RAISE EXCEPTION 'El archivo está vacío.' USING ERRCODE = '22023';
    END IF;
    IF length(v_bytes) > c_tamano_maximo THEN
        RAISE EXCEPTION 'El archivo pesa más de 5 MB.' USING ERRCODE = '22023';
    END IF;

    -- Codificación declarada en <?xml ... encoding="..."?>; sin declaración, UTF-8.
    IF substring(v_bytes FROM 1 FOR 3) = '\xefbbbf'::BYTEA THEN
        v_contenido := substring(v_bytes FROM 4);
        v_codificacion := 'UTF8';
    ELSE
        v_contenido := v_bytes;
        v_codificacion := COALESCE(
            substring(convert_from(substring(v_bytes FROM 1 FOR 200), 'LATIN1')
                      FROM '^\s*<\?xml[^>]*encoding\s*=\s*["'']([^"'']+)["'']'),
            'UTF8');
    END IF;

    BEGIN
        v_texto := convert_from(v_contenido, v_codificacion);
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'El archivo declara una codificación desconocida o tiene caracteres inválidos (%).',
            v_codificacion USING ERRCODE = '22023';
    END;
    -- El texto ya está en la codificación de la base: se quita la declaración.
    v_texto := regexp_replace(v_texto, '^\s*<\?xml[^>]*\?>', '');

    BEGIN
        v_doc := XMLPARSE(DOCUMENT v_texto);
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'El archivo no es un XML válido o está dañado.' USING ERRCODE = '22023';
    END;

    v_cantidad_docs := (xpath('count(' || c_documento || ')', v_doc))[1]::TEXT::NUMERIC::INTEGER;
    IF v_cantidad_docs = 0 THEN
        RAISE EXCEPTION 'El archivo no contiene un documento tributario electrónico (DTE).' USING ERRCODE = '22023';
    END IF;
    IF v_cantidad_docs > 1 THEN
        RAISE EXCEPTION 'El archivo contiene % documentos. Carga una factura a la vez.', v_cantidad_docs
            USING ERRCODE = '22023';
    END IF;

    -- Encabezado ----------------------------------------------------------------
    v_tipo := public.fn_dte_texto(v_doc, 'Encabezado/IdDoc/TipoDTE');
    IF v_tipo IS NULL THEN
        RAISE EXCEPTION 'No indica el tipo de documento (TipoDTE).' USING ERRCODE = '22023';
    END IF;
    IF v_tipo <> '33' THEN
        RAISE EXCEPTION 'El documento es tipo %. Solo se aceptan facturas electrónicas (tipo 33).', v_tipo
            USING ERRCODE = '22023';
    END IF;

    v_folio_txt := public.fn_dte_texto(v_doc, 'Encabezado/IdDoc/Folio');
    IF v_folio_txt IS NULL OR v_folio_txt !~ '^[0-9]{1,18}$' OR v_folio_txt::BIGINT <= 0 THEN
        RAISE EXCEPTION 'El folio falta o no es un número válido.' USING ERRCODE = '22023';
    END IF;
    v_folio := v_folio_txt::BIGINT;

    v_fecha_txt := public.fn_dte_texto(v_doc, 'Encabezado/IdDoc/FchEmis');
    BEGIN
        IF v_fecha_txt !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN
            RAISE EXCEPTION 'fecha';
        END IF;
        v_fecha := v_fecha_txt::DATE;
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'La fecha de emisión falta o no es válida.' USING ERRCODE = '22023';
    END;
    IF v_fecha IS NULL THEN
        RAISE EXCEPTION 'La fecha de emisión falta o no es válida.' USING ERRCODE = '22023';
    END IF;

    v_venc_txt := public.fn_dte_texto(v_doc, 'Encabezado/IdDoc/FchVenc');
    IF v_venc_txt IS NOT NULL THEN
        BEGIN
            IF v_venc_txt !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN
                RAISE EXCEPTION 'fecha';
            END IF;
            v_venc := v_venc_txt::DATE;
        EXCEPTION WHEN OTHERS THEN
            RAISE EXCEPTION 'La fecha de vencimiento no es válida.' USING ERRCODE = '22023';
        END;
    END IF;

    v_rut := public.fn_dte_texto(v_doc, 'Encabezado/Emisor/RUTEmisor');
    IF v_rut IS NULL THEN
        RAISE EXCEPTION 'No indica el RUT del emisor.' USING ERRCODE = '22023';
    END IF;
    v_rut_norm := public.fn_normalizar_rut(v_rut);
    IF v_rut_norm IS NULL THEN
        RAISE EXCEPTION 'El RUT del emisor (%) no es válido.', v_rut USING ERRCODE = '22023';
    END IF;

    v_neto   := CASE WHEN public.fn_dte_texto(v_doc, 'Encabezado/Totales/MntNeto') ~ '^-?[0-9]+$'
                     THEN public.fn_dte_texto(v_doc, 'Encabezado/Totales/MntNeto')::NUMERIC END;
    v_iva    := CASE WHEN public.fn_dte_texto(v_doc, 'Encabezado/Totales/IVA') ~ '^-?[0-9]+$'
                     THEN public.fn_dte_texto(v_doc, 'Encabezado/Totales/IVA')::NUMERIC END;
    v_total  := CASE WHEN public.fn_dte_texto(v_doc, 'Encabezado/Totales/MntTotal') ~ '^-?[0-9]+$'
                     THEN public.fn_dte_texto(v_doc, 'Encabezado/Totales/MntTotal')::NUMERIC END;
    v_exento := CASE WHEN public.fn_dte_texto(v_doc, 'Encabezado/Totales/MntExe') ~ '^-?[0-9]+$'
                     THEN public.fn_dte_texto(v_doc, 'Encabezado/Totales/MntExe')::NUMERIC ELSE 0 END;
    v_tasa   := CASE WHEN public.fn_dte_texto(v_doc, 'Encabezado/Totales/TasaIVA') ~ '^[0-9]+(\.[0-9]+)?$'
                     THEN public.fn_dte_texto(v_doc, 'Encabezado/Totales/TasaIVA')::NUMERIC END;
    IF v_neto IS NULL THEN
        RAISE EXCEPTION 'Falta el monto neto (MntNeto) o no es un número entero.' USING ERRCODE = '22023';
    END IF;
    IF v_iva IS NULL THEN
        RAISE EXCEPTION 'Falta el IVA o no es un número entero.' USING ERRCODE = '22023';
    END IF;
    IF v_total IS NULL THEN
        RAISE EXCEPTION 'Falta el monto total (MntTotal) o no es un número entero.' USING ERRCODE = '22023';
    END IF;

    v_otros_txt := (xpath('sum(' || c_documento || '/*[local-name()="Encabezado"]/*[local-name()="Totales"]'
                          || '/*[local-name()="ImptoReten"]/*[local-name()="MontoImp"])', v_doc))[1]::TEXT;
    IF v_otros_txt !~ '^-?[0-9]+(\.[0-9]+)?$' THEN
        RAISE EXCEPTION 'Los impuestos adicionales (ImptoReten) no son números válidos.' USING ERRCODE = '22023';
    END IF;
    v_otros := v_otros_txt::NUMERIC;

    IF v_neto + v_exento + v_iva + v_otros <> v_total THEN
        RAISE EXCEPTION 'Los totales no cuadran: neto, exento, IVA e impuestos suman %, pero el total informado es %.',
            v_neto + v_exento + v_iva + v_otros, v_total USING ERRCODE = '22023';
    END IF;

    v_incluye_iva := COALESCE(public.fn_dte_texto(v_doc, 'Encabezado/IdDoc/IndMntBruto') = '1', FALSE);
    v_forma_pago := public.fn_dte_texto(v_doc, 'Encabezado/IdDoc/FmaPago');
    v_orden_compra := NULLIF(btrim((xpath('string(' || c_documento
        || '/*[local-name()="Referencia"][*[local-name()="TpoDocRef"]="801"][1]/*[local-name()="FolioRef"])',
        v_doc))[1]::TEXT), '');

    -- ¿Ya fue ingresada? (H3.7) -------------------------------------------------------
    -- El candado serializa dos confirmaciones de la misma factura (doble clic o dos
    -- sesiones): la segunda espera y luego ve la primera. La restricción única es la
    -- última defensa.
    PERFORM pg_advisory_xact_lock(hashtext('factura_xml:' || v_rut_norm || ':33:' || v_folio));

    SELECT f.id INTO v_existente
      FROM public.facturas_compra f
     WHERE f.rut_emisor_normalizado = v_rut_norm AND f.tipo_documento = 33 AND f.folio = v_folio;
    IF FOUND THEN
        RAISE EXCEPTION 'Esta factura ya fue ingresada (folio % del emisor %).', v_folio, v_rut_norm
            USING ERRCODE = '23505', DETAIL = 'factura_compra_id=' || v_existente;
    END IF;

    -- Proveedor por RUT; si no existe queda NULL (decidido el 16/10/2026).
    SELECT p.id INTO v_proveedor
      FROM public.proveedores p
     WHERE public.fn_normalizar_rut(p.rut) = v_rut_norm
     LIMIT 1;

    -- Cabeceras ------------------------------------------------------------------
    INSERT INTO public.facturas_compra
        (proveedor_id, sucursal_id, numero_factura, fecha_factura, monto_neto, monto_iva,
         monto_impuestos_especificos, monto_total, estado, origen,
         rut_emisor_normalizado, tipo_documento, folio)
    VALUES
        (v_proveedor, p_sucursal_id, v_folio::TEXT, v_fecha, v_neto, v_iva,
         v_otros, v_total, 'confirmada', 'xml',
         v_rut_norm, 33, v_folio)
    RETURNING id INTO v_factura;

    INSERT INTO public.facturas_xml_pendientes
        (sucursal_id, cargado_por, estado, tipo_documento, folio, rut_emisor, rut_emisor_normalizado,
         razon_social_emisor, rut_receptor, fecha_emision, fecha_vencimiento, forma_pago,
         orden_compra_referencia, monto_neto, monto_iva, tasa_iva, monto_total,
         xml_original, xml_nombre, xml_sha256, detalle_incluye_iva,
         factura_id, confirmado_por, confirmado_en)
    VALUES
        (p_sucursal_id, v_actor, 'confirmada', 33, v_folio, left(v_rut, 12), v_rut_norm,
         left(public.fn_dte_texto(v_doc, 'Encabezado/Emisor/RznSoc'), 150),
         left(public.fn_dte_texto(v_doc, 'Encabezado/Receptor/RUTRecep'), 12),
         v_fecha, v_venc,
         CASE WHEN v_forma_pago ~ '^[0-9]{1,4}$' THEN v_forma_pago::SMALLINT END,
         left(v_orden_compra, 60), v_neto, v_iva, v_tasa, v_total,
         v_bytes, left(p_xml_nombre, 255), encode(sha256(v_bytes), 'hex'), v_incluye_iva,
         v_factura, v_actor, now())
    RETURNING id INTO v_pendiente;

    -- Líneas -------------------------------------------------------------------------
    v_total_lineas := (xpath('count(' || c_documento || '/*[local-name()="Detalle"])', v_doc))[1]::TEXT::NUMERIC::INTEGER;
    IF v_total_lineas = 0 THEN
        RAISE EXCEPTION 'La factura no trae líneas de detalle.' USING ERRCODE = '22023';
    END IF;

    FOR v_pos IN 1..v_total_lineas LOOP
        v_nro_txt := public.fn_dte_texto(v_doc, 'NroLinDet', v_pos);
        v_nro := CASE WHEN v_nro_txt ~ '^[0-9]{1,9}$' THEN v_nro_txt::INTEGER ELSE v_pos END;
        IF v_nro = ANY (v_numeros) THEN
            RAISE EXCEPTION 'La factura repite el número de línea %.', v_nro USING ERRCODE = '22023';
        END IF;
        v_numeros := v_numeros || v_nro;

        v_desc := public.fn_dte_texto(v_doc, 'NmbItem', v_pos);
        v_codigo := public.fn_dte_texto(v_doc, 'CdgItem/VlrCodigo', v_pos);
        v_codigo_tipo := public.fn_dte_texto(v_doc, 'CdgItem/TpoCodigo', v_pos);
        v_qty_txt := public.fn_dte_texto(v_doc, 'QtyItem', v_pos);
        v_prc_txt := public.fn_dte_texto(v_doc, 'PrcItem', v_pos);
        v_monto_txt := public.fn_dte_texto(v_doc, 'MontoItem', v_pos);

        IF v_desc IS NULL THEN
            RAISE EXCEPTION 'Línea %: falta la descripción del artículo.', v_nro USING ERRCODE = '22023';
        END IF;
        IF v_qty_txt IS NULL OR v_qty_txt !~ '^[0-9]+(\.[0-9]+)?$' OR v_qty_txt::NUMERIC <= 0 THEN
            RAISE EXCEPTION 'Línea %: la cantidad falta o no es mayor que cero.', v_nro USING ERRCODE = '22023';
        END IF;
        IF v_prc_txt IS NULL OR v_prc_txt !~ '^[0-9]+(\.[0-9]+)?$' THEN
            RAISE EXCEPTION 'Línea %: falta el precio unitario.', v_nro USING ERRCODE = '22023';
        END IF;
        IF v_monto_txt IS NULL OR v_monto_txt !~ '^-?[0-9]+$' THEN
            RAISE EXCEPTION 'Línea %: falta el monto de la línea.', v_nro USING ERRCODE = '22023';
        END IF;
        v_qty := v_qty_txt::NUMERIC;
        v_prc := v_prc_txt::NUMERIC;
        v_monto := v_monto_txt::NUMERIC;

        -- Qué eligió el usuario para esta línea.
        SELECT count(*) INTO v_cuenta
          FROM jsonb_array_elements(p_lineas) e
         WHERE e->>'numero_linea' = v_nro::TEXT;
        IF v_cuenta > 1 THEN
            RAISE EXCEPTION 'La línea % aparece más de una vez en la asociación.', v_nro USING ERRCODE = '22023';
        END IF;
        SELECT e INTO v_asoc
          FROM jsonb_array_elements(p_lineas) e
         WHERE e->>'numero_linea' = v_nro::TEXT;

        v_ingrediente := CASE WHEN v_asoc->>'ingrediente_id' ~ '^[0-9]{1,9}$'
                              THEN (v_asoc->>'ingrediente_id')::INTEGER END;
        v_producto := CASE WHEN v_asoc->>'producto_id' ~ '^[0-9]{1,9}$'
                           THEN (v_asoc->>'producto_id')::INTEGER END;
        v_no_inventario := COALESCE(v_asoc->'no_corresponde_inventario' = 'true'::JSONB, FALSE);
        v_equivalencia := CASE WHEN jsonb_typeof(v_asoc->'unidades_por_presentacion') = 'number'
                               THEN (v_asoc->>'unidades_por_presentacion')::NUMERIC END;

        IF num_nonnulls(v_ingrediente, v_producto) + (CASE WHEN v_no_inventario THEN 1 ELSE 0 END) > 1 THEN
            RAISE EXCEPTION 'La línea % tiene más de una clasificación.', v_nro USING ERRCODE = '22023';
        END IF;

        IF v_asoc IS NULL OR (num_nonnulls(v_ingrediente, v_producto) = 0 AND NOT v_no_inventario) THEN
            v_sin_asociar := v_sin_asociar + 1;
            CONTINUE;
        END IF;

        IF v_no_inventario THEN
            INSERT INTO public.facturas_xml_pendientes_lineas
                (factura_xml_id, numero_linea, codigo_tipo, codigo_proveedor, descripcion,
                 cantidad, precio_unitario, monto, no_corresponde_inventario)
            VALUES
                (v_pendiente, v_nro, left(v_codigo_tipo, 20), left(v_codigo, 60), left(v_desc, 255),
                 v_qty, v_prc, v_monto, TRUE);
            v_lineas_otras := v_lineas_otras + 1;
            CONTINUE;
        END IF;

        IF v_equivalencia IS NULL OR v_equivalencia <= 0 OR v_equivalencia <> round(v_equivalencia, 3) THEN
            v_sin_equivalencia := v_sin_equivalencia + 1;
            CONTINUE;
        END IF;

        IF v_ingrediente IS NOT NULL THEN
            SELECT i.unidad_id INTO v_unidad
              FROM public.ingredientes i
             WHERE i.id = v_ingrediente AND i.activo;
            IF NOT FOUND THEN
                RAISE EXCEPTION 'Línea %: la materia prima elegida no existe o está inactiva.', v_nro
                    USING ERRCODE = '22023';
            END IF;
        ELSE
            IF NOT EXISTS (SELECT 1 FROM public.productos p WHERE p.id = v_producto AND p.activo) THEN
                RAISE EXCEPTION 'Línea %: el producto elegido no existe o está inactivo.', v_nro
                    USING ERRCODE = '22023';
            END IF;
            IF EXISTS (SELECT 1 FROM public.recetas r WHERE r.producto_id = v_producto) THEN
                RAISE EXCEPTION 'Línea %: el producto elegido tiene receta; su stock sale de sus ingredientes.', v_nro
                    USING ERRCODE = '22023';
            END IF;
            v_unidad := NULL;
        END IF;

        v_cantidad := round(v_qty * v_equivalencia, 3);
        IF v_cantidad <= 0 THEN
            RAISE EXCEPTION 'Línea %: la cantidad a ingresar es demasiado pequeña.', v_nro USING ERRCODE = '22023';
        END IF;

        INSERT INTO public.facturas_xml_pendientes_lineas
            (factura_xml_id, numero_linea, codigo_tipo, codigo_proveedor, descripcion,
             cantidad, precio_unitario, monto, ingrediente_id, producto_id, unidades_por_presentacion)
        VALUES
            (v_pendiente, v_nro, left(v_codigo_tipo, 20), left(v_codigo, 60), left(v_desc, 255),
             v_qty, v_prc, v_monto, v_ingrediente, v_producto, v_equivalencia);

        -- Costo neto de la línea; si los montos incluyen IVA, se le descuenta.
        v_costo := CASE WHEN v_incluye_iva
                        THEN round(v_monto / (1 + COALESCE(v_tasa, 19) / 100), 2)
                        ELSE v_monto END;
        v_precio := round(v_costo / v_cantidad, 2);

        -- El stock lo suma fn_aplicar_compra (AFTER INSERT), una sola vez por fila.
        INSERT INTO public.detalle_factura_compra
            (factura_id, ingrediente_id, producto_id, codigo_proveedor, unidades_por_presentacion,
             cantidad, unidad_id, precio_unitario, descuento_monto)
        VALUES
            (v_factura, v_ingrediente, v_producto, left(v_codigo, 30),
             CASE WHEN v_equivalencia = round(v_equivalencia, 2) AND v_equivalencia < 100000000
                  THEN v_equivalencia END,
             v_cantidad, v_unidad, v_precio,
             -- Diferencia de redondeo de precio_unitario (2 decimales): así subtotal_neto
             -- es exactamente el monto de la línea.
             round(v_cantidad * v_precio, 2) - v_costo);

        v_lineas_stock := v_lineas_stock + 1;
    END LOOP;

    IF v_sin_asociar > 0 THEN
        RAISE EXCEPTION 'Faltan asociar % línea(s): elige un artículo o márcalas como «No corresponde a inventario».',
            v_sin_asociar USING ERRCODE = '22023';
    END IF;
    IF v_sin_equivalencia > 0 THEN
        RAISE EXCEPTION 'Falta la equivalencia de % línea(s) asociadas a un artículo.', v_sin_equivalencia
            USING ERRCODE = '22023';
    END IF;
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_lineas) e
                WHERE NOT (e->>'numero_linea' ~ '^[0-9]{1,9}$'
                           AND (e->>'numero_linea')::INTEGER = ANY (v_numeros))) THEN
        RAISE EXCEPTION 'La asociación menciona líneas que no están en la factura.' USING ERRCODE = '22023';
    END IF;

    RETURN jsonb_build_object(
        'factura_compra_id', v_factura,
        'factura_xml_id', v_pendiente,
        'lineas_inventario', v_lineas_stock,
        'lineas_no_inventario', v_lineas_otras);
END;
$$;

-- Solo roles de inventario. Las funciones auxiliares no se publican como RPC.
REVOKE ALL ON FUNCTION public.fn_ingresar_factura_xml(integer, text, text, jsonb)
    FROM PUBLIC, web_anon, nury_cajero;
GRANT EXECUTE ON FUNCTION public.fn_ingresar_factura_xml(integer, text, text, jsonb)
    TO nury_admin, nury_bodeguero;
REVOKE ALL ON FUNCTION public.fn_dte_texto(xml, text, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_normalizar_rut(text) FROM PUBLIC;

COMMIT;


-- #####################################################################
-- 20. database/migrations/20261017_permisos_ingreso_facturas.sql
-- #####################################################################

-- Permisos y sucursal para el ingreso de facturas XML (H3.1 T07).
--
-- Regla (decidida el 16/10/2026):
--   - admin: puede ingresar facturas en cualquier sucursal activa.
--   - bodeguero: solo en su propia sucursal (usuarios.sucursal_id). Sin sucursal
--     asignada no puede ingresar.
--   - cajero y cualquier otro rol: no ingresan facturas.
--
-- Se valida aquí, en PostgreSQL, y no solo en pantalla:
--   1. fn_actor_ingreso(): identifica al usuario de la sesión por el JWT, igual que
--      fn_usuario_actual_id() (que no reconoce al bodeguero y no se modifica).
--   2. fn_validar_sucursal_ingreso(): rechaza una sucursal que el usuario no puede usar.
--      La reutilizará la confirmación transaccional (H3.1 T08).
--   3. Disparador sobre facturas_xml_pendientes: valida la sucursal al insertar o
--      modificarla y fija cargado_por con el usuario real, no con lo que envíe el cliente.
--   4. RLS: el bodeguero solo ve y toca filas de su sucursal; el admin, todas.
--      Los demás roles quedan sin acceso.
--
-- REQUIERE: 20261016_facturas_xml_pendientes.sql aplicado, y los roles JWT
-- nury_admin, nury_cajero, nury_bodeguero y web_anon (ver 20261012_permisos_cajero.sql).
--
-- ANTES DE APLICAR EN PRODUCCIÓN:
--   a) Revisar el script completo con el responsable.
--   b) Correr primero 20261017_permisos_ingreso_facturas.ENSAYO.sql (termina en ROLLBACK).
--   c) Después de aplicar: NOTIFY pgrst, 'reload schema';

BEGIN;

-- 1) Quién es el usuario de la sesión ------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_actor_ingreso()
RETURNS TABLE (usuario_id INTEGER, rol TEXT, sucursal_id INTEGER)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    WITH sesion AS (
        SELECT COALESCE(NULLIF(current_setting('request.jwt.claims', TRUE), ''), '{}')::jsonb AS claims
    ), identidad AS (
        SELECT claims->>'role' AS rol_jwt,
               COALESCE(claims->>'user_id', claims->>'usuario_id', claims->>'sub', claims->>'id') AS id
          FROM sesion
    )
    SELECT u.id, u.rol::TEXT, u.sucursal_id
      FROM public.usuarios u, identidad i
     WHERE u.id = CASE WHEN i.id ~ '^[0-9]{1,10}$' THEN i.id::bigint ELSE NULL END
       AND u.activo
       -- El rol del JWT debe coincidir con el rol real del usuario en la base.
       AND CASE WHEN u.rol IN ('admin', 'administrador') THEN 'nury_admin'
                WHEN u.rol = 'bodeguero' THEN 'nury_bodeguero' END = i.rol_jwt;
$$;

REVOKE ALL ON FUNCTION public.fn_actor_ingreso() FROM PUBLIC, web_anon, nury_cajero;
GRANT EXECUTE ON FUNCTION public.fn_actor_ingreso() TO nury_admin, nury_bodeguero;

-- 2) ¿Puede este usuario ingresar en esa sucursal? --------------------------------

CREATE OR REPLACE FUNCTION public.fn_validar_sucursal_ingreso(p_sucursal_id INTEGER)
RETURNS INTEGER
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor  RECORD;
BEGIN
    SELECT * INTO v_actor FROM public.fn_actor_ingreso();
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Tu usuario no está autorizado para ingresar facturas'
            USING ERRCODE = '42501';
    END IF;

    IF p_sucursal_id IS NULL THEN
        RAISE EXCEPTION 'Indica la sucursal que recibirá el stock'
            USING ERRCODE = '22023';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.sucursales WHERE id = p_sucursal_id AND activo) THEN
        RAISE EXCEPTION 'La sucursal indicada no existe o está inactiva'
            USING ERRCODE = '23503';
    END IF;

    IF v_actor.rol NOT IN ('admin', 'administrador') THEN
        IF v_actor.sucursal_id IS NULL THEN
            RAISE EXCEPTION 'Tu usuario no tiene una sucursal asignada: no puede ingresar facturas'
                USING ERRCODE = '42501';
        END IF;
        IF v_actor.sucursal_id <> p_sucursal_id THEN
            RAISE EXCEPTION 'Solo puedes ingresar facturas en tu propia sucursal'
                USING ERRCODE = '42501';
        END IF;
    END IF;

    RETURN v_actor.usuario_id;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_validar_sucursal_ingreso(integer) FROM PUBLIC, web_anon, nury_cajero;
GRANT EXECUTE ON FUNCTION public.fn_validar_sucursal_ingreso(integer) TO nury_admin, nury_bodeguero;

-- 3) Disparador sobre la factura pendiente ---------------------------------------

CREATE OR REPLACE FUNCTION public.fn_facturas_xml_permisos()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    v_usuario INTEGER;
BEGIN
    v_usuario := public.fn_validar_sucursal_ingreso(NEW.sucursal_id);

    IF TG_OP = 'INSERT' THEN
        -- Quien carga es quien tiene la sesión, no lo que envíe el cliente.
        NEW.cargado_por := v_usuario;
    ELSE
        -- Quién cargó la factura no se cambia después.
        NEW.cargado_por := OLD.cargado_por;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_facturas_xml_permisos ON public.facturas_xml_pendientes;
CREATE TRIGGER trg_facturas_xml_permisos
BEFORE INSERT OR UPDATE ON public.facturas_xml_pendientes
FOR EACH ROW EXECUTE FUNCTION public.fn_facturas_xml_permisos();

-- 4) Acceso a las tablas ----------------------------------------------------------

ALTER TABLE public.facturas_xml_pendientes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.facturas_xml_pendientes_lineas ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS facturas_xml_admin ON public.facturas_xml_pendientes;
CREATE POLICY facturas_xml_admin ON public.facturas_xml_pendientes
    TO nury_admin USING (TRUE) WITH CHECK (TRUE);

DROP POLICY IF EXISTS facturas_xml_bodeguero ON public.facturas_xml_pendientes;
CREATE POLICY facturas_xml_bodeguero ON public.facturas_xml_pendientes
    TO nury_bodeguero
    USING (sucursal_id = (SELECT a.sucursal_id FROM public.fn_actor_ingreso() a))
    WITH CHECK (sucursal_id = (SELECT a.sucursal_id FROM public.fn_actor_ingreso() a));

-- Las líneas siguen a su factura: la subconsulta ya está filtrada por la política anterior.
DROP POLICY IF EXISTS facturas_xml_lineas_admin ON public.facturas_xml_pendientes_lineas;
CREATE POLICY facturas_xml_lineas_admin ON public.facturas_xml_pendientes_lineas
    TO nury_admin USING (TRUE) WITH CHECK (TRUE);

DROP POLICY IF EXISTS facturas_xml_lineas_bodeguero ON public.facturas_xml_pendientes_lineas;
CREATE POLICY facturas_xml_lineas_bodeguero ON public.facturas_xml_pendientes_lineas
    TO nury_bodeguero
    USING (EXISTS (SELECT 1 FROM public.facturas_xml_pendientes f WHERE f.id = factura_xml_id))
    WITH CHECK (EXISTS (SELECT 1 FROM public.facturas_xml_pendientes f WHERE f.id = factura_xml_id));

-- Solo admin y bodeguero llegan a las tablas. Se reemplazan los permisos copiados de
-- facturas_compra en 20261016 (el cajero y web_anon no deben tener ninguno).
REVOKE ALL ON public.facturas_xml_pendientes, public.facturas_xml_pendientes_lineas
    FROM PUBLIC, web_anon, nury_cajero;
REVOKE ALL ON SEQUENCE public.facturas_xml_pendientes_id_seq, public.facturas_xml_pendientes_lineas_id_seq
    FROM PUBLIC, web_anon, nury_cajero;

GRANT USAGE ON SCHEMA public TO nury_admin, nury_bodeguero;
GRANT SELECT, INSERT, UPDATE ON public.facturas_xml_pendientes TO nury_admin, nury_bodeguero;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.facturas_xml_pendientes_lineas TO nury_admin, nury_bodeguero;
GRANT USAGE ON SEQUENCE public.facturas_xml_pendientes_id_seq,
                        public.facturas_xml_pendientes_lineas_id_seq TO nury_admin, nury_bodeguero;

COMMIT;


-- #####################################################################
-- 21. database/migrations/20261017_stock_insuficiente_venta.sql
-- #####################################################################

-- H2.5 T04 - Devolver al POS los ingredientes (y productos de reventa) que
-- quedaron con stock insuficiente después de una venta.
--
-- Cómo se conecta con el descuento de H3.2: la venta descuenta stock en el
-- trigger fn_aplicar_venta, que deja un movimiento 'venta' en el kardex por cada
-- ingrediente de la receta (o por el producto de reventa). Esta función lee esos
-- movimientos: no recalcula recetas ni vuelve a tocar el stock.
--
-- Regla (opción A acordada): la venta NO se bloquea por falta de stock; el stock
-- puede quedar negativo. Esta función solo informa, para que el POS avise.
--
-- "Insuficiente" = el stock que había antes de la venta no alcanzaba para lo que
-- la venta consumió, es decir, el stock quedó bajo cero después del descuento.
-- Un ingrediente compartido por varios productos de la misma venta se evalúa con
-- el consumo sumado (H2.5 T03).
--
-- No modifica fn_registrar_venta (la mantienen otros integrantes): el POS llama a
-- esta función justo después de registrar la venta.
--
-- Requiere: 0004_stock_producto_reventa.sql y 20261012_permisos_cajero.sql
-- (fn_usuario_actual_id).
--
-- ANTES DE APLICAR EN PRODUCCIÓN:
--   a) Correr 20261017_stock_insuficiente_venta.ENSAYO.sql (termina en ROLLBACK).
--   b) Después de aplicar: NOTIFY pgrst, 'reload schema';

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_stock_insuficiente_venta(p_venta_id INTEGER)
RETURNS TABLE (
    tipo           TEXT,           -- 'ingrediente' o 'producto'
    item_id        INTEGER,
    nombre         TEXT,
    sucursal_id    INTEGER,
    unidad         TEXT,
    requerido      NUMERIC,        -- lo que consumió la venta (sumado si se comparte)
    disponible     NUMERIC,        -- stock que había antes de la venta
    faltante       NUMERIC,        -- lo que no alcanzó a cubrir el stock
    stock_actual   NUMERIC         -- stock que quedó después de la venta
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $function$
DECLARE
    v_actor_id  INTEGER := public.fn_usuario_actual_id();
    v_actor_rol TEXT;
    v_cajero_id INTEGER;
BEGIN
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'La sesión no identifica a un usuario autorizado' USING ERRCODE = '42501';
    END IF;

    SELECT cajero_id INTO v_cajero_id FROM public.ventas WHERE id = p_venta_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La venta no existe' USING ERRCODE = '22023';
    END IF;

    -- Igual que en la anulación: un cajero solo consulta sus propias ventas.
    SELECT rol INTO v_actor_rol FROM public.usuarios WHERE id = v_actor_id;
    IF v_actor_rol = 'cajero' AND v_cajero_id IS DISTINCT FROM v_actor_id THEN
        RAISE EXCEPTION 'Solo puedes consultar tus propias ventas' USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    WITH movs AS (
        SELECT m.id, m.ingrediente_id, m.producto_id, m.sucursal_id, m.cantidad, m.stock_resultante
          FROM public.movimientos_stock m
         WHERE m.tipo_movimiento = 'venta'
           AND m.referencia_tipo = 'venta'
           AND m.referencia_id = p_venta_id
    ), por_item AS (
        SELECT DISTINCT ON (mv.ingrediente_id, mv.producto_id, mv.sucursal_id)
               mv.ingrediente_id, mv.producto_id, mv.sucursal_id,
               -SUM(mv.cantidad) OVER w AS requerido,
               mv.stock_resultante AS final            -- el último movimiento del ítem en la venta
          FROM movs mv
        WINDOW w AS (PARTITION BY mv.ingrediente_id, mv.producto_id, mv.sucursal_id)
         ORDER BY mv.ingrediente_id, mv.producto_id, mv.sucursal_id, mv.id DESC
    )
    SELECT CASE WHEN p.ingrediente_id IS NOT NULL THEN 'ingrediente' ELSE 'producto' END,
           COALESCE(p.ingrediente_id, p.producto_id),
           COALESCE(i.nombre, pr.nombre)::TEXT,
           p.sucursal_id,
           CASE WHEN p.ingrediente_id IS NOT NULL THEN um.abreviatura::TEXT ELSE 'unid.' END,
           p.requerido,
           p.final + p.requerido,
           LEAST(p.requerido, -p.final),
           p.final
      FROM por_item p
      LEFT JOIN public.ingredientes i     ON i.id = p.ingrediente_id
      LEFT JOIN public.unidades_medida um ON um.id = i.unidad_id
      LEFT JOIN public.productos pr       ON pr.id = p.producto_id
     WHERE p.final < 0
     ORDER BY 3;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_stock_insuficiente_venta(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_stock_insuficiente_venta(integer) TO nury_admin, nury_cajero;

COMMIT;


-- #####################################################################
-- 22. database/migrations/20261020_consulta_ingresos_factura.sql
-- #####################################################################

-- Consulta de ingresos de facturas XML realizados (H3.1 T09).
--
-- fn_listar_ingresos_factura(): facturas confirmadas, de la más reciente a la más antigua,
-- con su detalle original, el artículo asociado a cada línea, la equivalencia, la cantidad
-- incorporada, las líneas excluidas (no inventariables), quién y cuándo la ingresó, en qué
-- sucursal, y los intentos de volver a ingresarla (H3.7 T07).
--
-- fn_xml_factura(id): el XML original tal cual llegó, en base64, para descargarlo.
--
-- Quién ve qué (misma regla que el ingreso, H3.1 T07):
--   - admin: todas las sucursales.
--   - bodeguero: solo las facturas ingresadas en su sucursal (y los intentos sobre ellas).
--   - cajero y anónimos: sin acceso.
-- Son funciones SECURITY DEFINER porque reúnen datos de tablas que el bodeguero no lee
-- directamente (usuarios, proveedores); la regla de sucursal se aplica aquí.
--
-- shortcut: devuelve como máximo p_limite facturas (100 por defecto) sin paginar ni filtrar;
-- agregar paginación y filtros por fecha o proveedor cuando haya cientos de ingresos.
--
-- REQUIERE: 20261017_permisos_ingreso_facturas.sql, 20261017_ingresar_factura_xml.sql y
-- 20261020_intentos_factura_duplicada.sql.
--
-- ANTES DE APLICAR EN PRODUCCIÓN:
--   a) Revisar el script completo con el responsable.
--   b) Correr primero 20261020_consulta_ingresos_factura.ENSAYO.sql (termina en ROLLBACK).
--   c) Después de aplicar: NOTIFY pgrst, 'reload schema';

BEGIN;

-- 1) Listado de ingresos -----------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_listar_ingresos_factura(p_limite INTEGER DEFAULT 100)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor RECORD;
    v_admin BOOLEAN;
BEGIN
    SELECT * INTO v_actor FROM public.fn_actor_ingreso();
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Tu usuario no está autorizado para consultar ingresos de facturas'
            USING ERRCODE = '42501';
    END IF;
    v_admin := v_actor.rol IN ('admin', 'administrador');

    RETURN COALESCE((
        SELECT jsonb_agg(ingreso ORDER BY orden DESC, id DESC)
          FROM (
            SELECT x.id, x.confirmado_en AS orden,
                   jsonb_build_object(
                       'factura_xml_id', x.id,
                       'factura_compra_id', x.factura_id,
                       'folio', x.folio,
                       'tipo_documento', x.tipo_documento,
                       'rut_emisor', x.rut_emisor,
                       'razon_social_emisor', x.razon_social_emisor,
                       'proveedor', p.nombre,
                       'fecha_emision', x.fecha_emision,
                       'monto_neto', x.monto_neto,
                       'monto_iva', x.monto_iva,
                       'monto_total', x.monto_total,
                       'detalle_incluye_iva', x.detalle_incluye_iva,
                       'xml_nombre', x.xml_nombre,
                       'sucursal_id', x.sucursal_id,
                       'sucursal', s.nombre,
                       'ingresada_por', u.nombre,
                       'ingresada_en', x.confirmado_en,
                       'lineas', COALESCE((
                           SELECT jsonb_agg(jsonb_build_object(
                                      'numero_linea', l.numero_linea,
                                      'codigo_proveedor', l.codigo_proveedor,
                                      'descripcion', l.descripcion,
                                      'cantidad', l.cantidad,
                                      'precio_unitario', l.precio_unitario,
                                      'monto', l.monto,
                                      'tipo', CASE WHEN l.ingrediente_id IS NOT NULL THEN 'ingrediente'
                                                   WHEN l.producto_id IS NOT NULL THEN 'producto'
                                                   ELSE 'no-inventario' END,
                                      'articulo', COALESCE(i.nombre, pr.nombre),
                                      'unidad', CASE WHEN l.ingrediente_id IS NOT NULL THEN um.abreviatura
                                                     WHEN l.producto_id IS NOT NULL THEN 'un' END,
                                      'unidades_por_presentacion', l.unidades_por_presentacion,
                                      'cantidad_ingreso', l.cantidad_ingreso)
                                  ORDER BY l.numero_linea)
                             FROM public.facturas_xml_pendientes_lineas l
                             LEFT JOIN public.ingredientes i ON i.id = l.ingrediente_id
                             LEFT JOIN public.unidades_medida um ON um.id = i.unidad_id
                             LEFT JOIN public.productos pr ON pr.id = l.producto_id
                            WHERE l.factura_xml_id = x.id), '[]'::jsonb),
                       'intentos_duplicados', COALESCE((
                           SELECT jsonb_agg(jsonb_build_object(
                                      'creado_en', d.creado_en,
                                      'usuario', du.nombre,
                                      'sucursal_solicitada', ds.nombre,
                                      'xml_nombre', d.xml_nombre)
                                  ORDER BY d.creado_en DESC, d.id DESC)
                             FROM public.intentos_factura_duplicada d
                             LEFT JOIN public.usuarios du ON du.id = d.usuario_id
                             LEFT JOIN public.sucursales ds ON ds.id = d.sucursal_solicitada_id
                            WHERE d.factura_compra_id = x.factura_id), '[]'::jsonb)
                   ) AS ingreso
              FROM public.facturas_xml_pendientes x
              LEFT JOIN public.facturas_compra f ON f.id = x.factura_id
              LEFT JOIN public.proveedores p ON p.id = f.proveedor_id
              LEFT JOIN public.sucursales s ON s.id = x.sucursal_id
              LEFT JOIN public.usuarios u ON u.id = x.confirmado_por
             WHERE x.estado = 'confirmada'
               AND (v_admin OR x.sucursal_id = v_actor.sucursal_id)
             ORDER BY x.confirmado_en DESC, x.id DESC
             LIMIT GREATEST(LEAST(COALESCE(p_limite, 100), 500), 1)
          ) t
    ), '[]'::jsonb);
END;
$$;

REVOKE ALL ON FUNCTION public.fn_listar_ingresos_factura(integer) FROM PUBLIC, web_anon, nury_cajero;
GRANT EXECUTE ON FUNCTION public.fn_listar_ingresos_factura(integer) TO nury_admin, nury_bodeguero;

-- 2) XML original para descargar ----------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_xml_factura(p_factura_xml_id INTEGER)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor RECORD;
    v_xml   RECORD;
BEGIN
    SELECT * INTO v_actor FROM public.fn_actor_ingreso();
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Tu usuario no está autorizado para descargar facturas'
            USING ERRCODE = '42501';
    END IF;

    SELECT x.xml_nombre, x.xml_original, x.folio INTO v_xml
      FROM public.facturas_xml_pendientes x
     WHERE x.id = p_factura_xml_id
       AND x.estado = 'confirmada'
       AND (v_actor.rol IN ('admin', 'administrador') OR x.sucursal_id = v_actor.sucursal_id);
    -- Mismo mensaje si no existe o si es de otra sucursal: no revela qué facturas hay.
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La factura no existe o no tienes acceso a ella'
            USING ERRCODE = '42501';
    END IF;

    RETURN jsonb_build_object(
        'xml_nombre', COALESCE(v_xml.xml_nombre, 'factura-' || v_xml.folio || '.xml'),
        'xml_base64', encode(v_xml.xml_original, 'base64'));
END;
$$;

REVOKE ALL ON FUNCTION public.fn_xml_factura(integer) FROM PUBLIC, web_anon, nury_cajero;
GRANT EXECUTE ON FUNCTION public.fn_xml_factura(integer) TO nury_admin, nury_bodeguero;

COMMIT;


-- #####################################################################
-- 23. database/migrations/20261020_consultar_factura_ingresada.sql
-- #####################################################################

-- Consulta «¿esta factura ya fue ingresada?» (H3.7 T03) y recuperación de un ingreso
-- cuya respuesta no llegó (H3.7 T05).
--
-- fn_consultar_factura_ingresada(rut_emisor, tipo_documento, folio) busca la identidad
-- de la factura (RUT normalizado + tipo + folio, la misma de la restricción única de
-- facturas_compra) y responde:
--   - identificacion_completa = false si el RUT, el tipo o el folio faltan o no son
--     válidos. No es un error: la pantalla muestra el aviso de «identificación incompleta».
--   - ingresada = false si no existe un ingreso confirmado.
--   - ingresada = true si existe. Cuánto se cuenta depende de los permisos (decidido el
--     20/10/2026):
--       * admin, o bodeguero de la sucursal donde se ingresó: todo el detalle (id de la
--         factura, sucursal, fecha, quién la ingresó, cuántas líneas sumaron stock).
--       * bodeguero de otra sucursal: solo que ya fue ingresada. No ve sucursal, fecha
--         ni usuario, igual que no ve esas filas en las tablas (RLS).
--       * cajero y anónimos: sin acceso.
--
-- Recuperar un ingreso (T05): si la respuesta de la confirmación se perdió, el usuario
-- reintenta y la restricción única rechaza la factura repetida, así que nunca se suma
-- stock dos veces. Esta consulta le devuelve el ingreso existente (ingresada_por_ti,
-- ingresada_en y las líneas) para que la pantalla le informe que sí se completó.
--
-- No modifica fn_ingresar_factura_xml ni el esquema.
--
-- REQUIERE: 20261017_permisos_ingreso_facturas.sql y 20261017_ingresar_factura_xml.sql.
--
-- ANTES DE APLICAR EN PRODUCCIÓN:
--   a) Revisar el script completo con el responsable.
--   b) Correr primero 20261020_consultar_factura_ingresada.ENSAYO.sql (termina en ROLLBACK).
--   c) Después de aplicar: NOTIFY pgrst, 'reload schema';

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_consultar_factura_ingresada(
    p_rut_emisor     TEXT,
    p_tipo_documento SMALLINT,
    p_folio          BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor    RECORD;
    v_rut_norm TEXT;
    v_factura  RECORD;
    v_inv      INTEGER;
    v_otras    INTEGER;
BEGIN
    SELECT * INTO v_actor FROM public.fn_actor_ingreso();
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Tu usuario no está autorizado para ingresar facturas'
            USING ERRCODE = '42501';
    END IF;

    v_rut_norm := public.fn_normalizar_rut(p_rut_emisor);
    IF v_rut_norm IS NULL OR p_tipo_documento IS NULL OR p_folio IS NULL OR p_folio <= 0 THEN
        RETURN jsonb_build_object('identificacion_completa', FALSE, 'ingresada', FALSE);
    END IF;

    SELECT f.id AS factura_id, f.sucursal_id, s.nombre AS sucursal,
           x.id AS xml_id, x.confirmado_por, x.confirmado_en, u.nombre AS ingresada_por
      INTO v_factura
      FROM public.facturas_compra f
      LEFT JOIN public.sucursales s ON s.id = f.sucursal_id
      LEFT JOIN public.facturas_xml_pendientes x ON x.factura_id = f.id
      LEFT JOIN public.usuarios u ON u.id = x.confirmado_por
     WHERE f.rut_emisor_normalizado = v_rut_norm
       AND f.tipo_documento = p_tipo_documento
       AND f.folio = p_folio;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('identificacion_completa', TRUE, 'ingresada', FALSE);
    END IF;

    -- Otra sucursal: se sabe que ya existe, pero no dónde, cuándo ni quién.
    IF v_actor.rol NOT IN ('admin', 'administrador')
       AND v_factura.sucursal_id IS DISTINCT FROM v_actor.sucursal_id THEN
        RETURN jsonb_build_object('identificacion_completa', TRUE, 'ingresada', TRUE,
                                  'puede_ver_detalle', FALSE);
    END IF;

    SELECT count(*) FILTER (WHERE NOT COALESCE(l.no_corresponde_inventario, FALSE)),
           count(*) FILTER (WHERE COALESCE(l.no_corresponde_inventario, FALSE))
      INTO v_inv, v_otras
      FROM public.facturas_xml_pendientes_lineas l
     WHERE l.factura_xml_id = v_factura.xml_id;

    RETURN jsonb_build_object(
        'identificacion_completa', TRUE,
        'ingresada', TRUE,
        'puede_ver_detalle', TRUE,
        'factura_compra_id', v_factura.factura_id,
        'factura_xml_id', v_factura.xml_id,
        'sucursal_id', v_factura.sucursal_id,
        'sucursal', v_factura.sucursal,
        'ingresada_en', v_factura.confirmado_en,
        'ingresada_por', v_factura.ingresada_por,
        'ingresada_por_ti', COALESCE(v_factura.confirmado_por = v_actor.usuario_id, FALSE),
        'lineas_inventario', v_inv,
        'lineas_no_inventario', v_otras);
END;
$$;

REVOKE ALL ON FUNCTION public.fn_consultar_factura_ingresada(text, smallint, bigint)
    FROM PUBLIC, web_anon, nury_cajero;
GRANT EXECUTE ON FUNCTION public.fn_consultar_factura_ingresada(text, smallint, bigint)
    TO nury_admin, nury_bodeguero;

COMMIT;


-- #####################################################################
-- 24. database/migrations/20261020_intentos_factura_duplicada.sql
-- #####################################################################

-- Registro de intentos de ingresar una factura XML repetida (H3.7 T07).
--
-- Cuando alguien confirma una factura que ya fue ingresada, fn_ingresar_factura_xml ya
-- no lanza un error: guarda el intento y devuelve {"ya_ingresada": true, "intento_id": N}.
-- Hay que devolver y no lanzar error porque un error deshace la transacción y con ella el
-- registro del intento. Nada cambia para el stock: no se guarda factura ni líneas.
--
-- Cada intento guarda: usuario, fecha, sucursal pedida, resultado, referencia al ingreso
-- existente (y su sucursal) y el nombre y la huella SHA-256 del archivo (así se ve si
-- era el mismo archivo con otro nombre). Solo se registran los duplicados reales: un XML
-- inválido, una sucursal sin permiso o un usuario sin autorización siguen siendo errores
-- y no dejan registro.
--
-- Quién puede consultarlo (decidido el 20/10/2026, por RLS):
--   - admin: todos los intentos.
--   - bodeguero: los pedidos desde su sucursal y los hechos sobre facturas ingresadas en
--     su sucursal.
--   - cajero y anónimos: nada. Nadie inserta, modifica ni borra a mano: solo lo hace la
--     función de ingreso.
--
-- Los intentos que ocurrieron antes de este script no quedaron registrados.
--
-- REQUIERE: 20261017_permisos_ingreso_facturas.sql y 20261017_ingresar_factura_xml.sql.
-- Reemplaza fn_ingresar_factura_xml: el resto de la función es idéntico a 20261017.
--
-- ANTES DE APLICAR EN PRODUCCIÓN:
--   a) Revisar el script completo con el responsable.
--   b) Correr primero 20261020_intentos_factura_duplicada.ENSAYO.sql (termina en ROLLBACK).
--   c) Después de aplicar: NOTIFY pgrst, 'reload schema';

BEGIN;

-- 1) Tabla de intentos ------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.intentos_factura_duplicada (
    id                      SERIAL PRIMARY KEY,
    creado_en               TIMESTAMP NOT NULL DEFAULT now(),
    usuario_id              INTEGER NOT NULL REFERENCES public.usuarios(id),
    sucursal_solicitada_id  INTEGER NOT NULL REFERENCES public.sucursales(id),
    rut_emisor_normalizado  VARCHAR(12) NOT NULL,
    tipo_documento          SMALLINT NOT NULL,
    folio                   BIGINT NOT NULL,
    factura_compra_id       INTEGER NOT NULL REFERENCES public.facturas_compra(id),
    sucursal_factura_id     INTEGER NOT NULL REFERENCES public.sucursales(id),
    resultado               VARCHAR(20) NOT NULL DEFAULT 'rechazado'
                            CHECK (resultado IN ('rechazado')),
    xml_nombre              VARCHAR(255),
    xml_sha256              VARCHAR(64)
);

CREATE INDEX IF NOT EXISTS idx_intentos_factura_duplicada_factura
    ON public.intentos_factura_duplicada (factura_compra_id, creado_en DESC);

-- 2) Acceso: solo lectura según el rol --------------------------------------------------

ALTER TABLE public.intentos_factura_duplicada ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS intentos_duplicada_admin ON public.intentos_factura_duplicada;
CREATE POLICY intentos_duplicada_admin ON public.intentos_factura_duplicada
    FOR SELECT TO nury_admin USING (TRUE);

DROP POLICY IF EXISTS intentos_duplicada_bodeguero ON public.intentos_factura_duplicada;
CREATE POLICY intentos_duplicada_bodeguero ON public.intentos_factura_duplicada
    FOR SELECT TO nury_bodeguero
    USING (sucursal_solicitada_id = (SELECT a.sucursal_id FROM public.fn_actor_ingreso() a)
        OR sucursal_factura_id    = (SELECT a.sucursal_id FROM public.fn_actor_ingreso() a));

REVOKE ALL ON public.intentos_factura_duplicada
    FROM PUBLIC, web_anon, nury_cajero, nury_admin, nury_bodeguero;
REVOKE ALL ON SEQUENCE public.intentos_factura_duplicada_id_seq
    FROM PUBLIC, web_anon, nury_cajero, nury_admin, nury_bodeguero;
GRANT SELECT ON public.intentos_factura_duplicada TO nury_admin, nury_bodeguero;

-- 3) Ingreso completo de la factura (igual a 20261017, salvo el bloque marcado) ----------

CREATE OR REPLACE FUNCTION public.fn_ingresar_factura_xml(
    p_sucursal_id INTEGER,
    p_xml_base64  TEXT,
    p_xml_nombre  TEXT,
    p_lineas      JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    c_documento CONSTANT TEXT := '//*[local-name()="Documento"]';
    c_tamano_maximo CONSTANT INTEGER := 5 * 1024 * 1024;

    v_actor            INTEGER;
    v_bytes            BYTEA;
    v_contenido        BYTEA;
    v_codificacion     TEXT;
    v_texto            TEXT;
    v_doc              XML;
    v_cantidad_docs    INTEGER;

    v_tipo             TEXT;
    v_folio_txt        TEXT;
    v_folio            BIGINT;
    v_fecha_txt        TEXT;
    v_fecha            DATE;
    v_venc_txt         TEXT;
    v_venc             DATE;
    v_rut              TEXT;
    v_rut_norm         TEXT;
    v_neto             NUMERIC;
    v_exento           NUMERIC;
    v_iva              NUMERIC;
    v_total            NUMERIC;
    v_tasa             NUMERIC;
    v_otros_txt        TEXT;
    v_otros            NUMERIC;
    v_incluye_iva      BOOLEAN;
    v_forma_pago       TEXT;
    v_orden_compra     TEXT;

    v_existente        INTEGER;
    v_suc_existente    INTEGER;
    v_intento          INTEGER;
    v_proveedor        INTEGER;
    v_factura          INTEGER;
    v_pendiente        INTEGER;

    v_total_lineas     INTEGER;
    v_numeros          INTEGER[] := '{}';
    v_pos              INTEGER;
    v_nro              INTEGER;
    v_nro_txt          TEXT;
    v_desc             TEXT;
    v_codigo           TEXT;
    v_codigo_tipo      TEXT;
    v_qty_txt          TEXT;
    v_qty              NUMERIC;
    v_prc_txt          TEXT;
    v_prc              NUMERIC;
    v_monto_txt        TEXT;
    v_monto            NUMERIC;

    v_cuenta           INTEGER;
    v_asoc             JSONB;
    v_ingrediente      INTEGER;
    v_producto         INTEGER;
    v_no_inventario    BOOLEAN;
    v_equivalencia     NUMERIC;
    v_unidad           INTEGER;
    v_cantidad         NUMERIC;
    v_costo            NUMERIC;
    v_precio           NUMERIC;

    v_sin_asociar      INTEGER := 0;
    v_sin_equivalencia INTEGER := 0;
    v_lineas_stock     INTEGER := 0;
    v_lineas_otras     INTEGER := 0;
BEGIN
    -- Permiso y sucursal (42501 si no corresponde).
    v_actor := public.fn_validar_sucursal_ingreso(p_sucursal_id);

    IF p_lineas IS NULL OR jsonb_typeof(p_lineas) <> 'array' THEN
        RAISE EXCEPTION 'Indica qué hacer con cada línea de la factura' USING ERRCODE = '22023';
    END IF;

    -- Archivo ------------------------------------------------------------------
    BEGIN
        v_bytes := decode(COALESCE(p_xml_base64, ''), 'base64');
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'El archivo no llegó completo. Vuelve a elegirlo.' USING ERRCODE = '22023';
    END;
    IF length(v_bytes) = 0 THEN
        RAISE EXCEPTION 'El archivo está vacío.' USING ERRCODE = '22023';
    END IF;
    IF length(v_bytes) > c_tamano_maximo THEN
        RAISE EXCEPTION 'El archivo pesa más de 5 MB.' USING ERRCODE = '22023';
    END IF;

    -- Codificación declarada en <?xml ... encoding="..."?>; sin declaración, UTF-8.
    IF substring(v_bytes FROM 1 FOR 3) = '\xefbbbf'::BYTEA THEN
        v_contenido := substring(v_bytes FROM 4);
        v_codificacion := 'UTF8';
    ELSE
        v_contenido := v_bytes;
        v_codificacion := COALESCE(
            substring(convert_from(substring(v_bytes FROM 1 FOR 200), 'LATIN1')
                      FROM '^\s*<\?xml[^>]*encoding\s*=\s*["'']([^"'']+)["'']'),
            'UTF8');
    END IF;

    BEGIN
        v_texto := convert_from(v_contenido, v_codificacion);
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'El archivo declara una codificación desconocida o tiene caracteres inválidos (%).',
            v_codificacion USING ERRCODE = '22023';
    END;
    -- El texto ya está en la codificación de la base: se quita la declaración.
    v_texto := regexp_replace(v_texto, '^\s*<\?xml[^>]*\?>', '');

    BEGIN
        v_doc := XMLPARSE(DOCUMENT v_texto);
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'El archivo no es un XML válido o está dañado.' USING ERRCODE = '22023';
    END;

    v_cantidad_docs := (xpath('count(' || c_documento || ')', v_doc))[1]::TEXT::NUMERIC::INTEGER;
    IF v_cantidad_docs = 0 THEN
        RAISE EXCEPTION 'El archivo no contiene un documento tributario electrónico (DTE).' USING ERRCODE = '22023';
    END IF;
    IF v_cantidad_docs > 1 THEN
        RAISE EXCEPTION 'El archivo contiene % documentos. Carga una factura a la vez.', v_cantidad_docs
            USING ERRCODE = '22023';
    END IF;

    -- Encabezado ----------------------------------------------------------------
    v_tipo := public.fn_dte_texto(v_doc, 'Encabezado/IdDoc/TipoDTE');
    IF v_tipo IS NULL THEN
        RAISE EXCEPTION 'No indica el tipo de documento (TipoDTE).' USING ERRCODE = '22023';
    END IF;
    IF v_tipo <> '33' THEN
        RAISE EXCEPTION 'El documento es tipo %. Solo se aceptan facturas electrónicas (tipo 33).', v_tipo
            USING ERRCODE = '22023';
    END IF;

    v_folio_txt := public.fn_dte_texto(v_doc, 'Encabezado/IdDoc/Folio');
    IF v_folio_txt IS NULL OR v_folio_txt !~ '^[0-9]{1,18}$' OR v_folio_txt::BIGINT <= 0 THEN
        RAISE EXCEPTION 'El folio falta o no es un número válido.' USING ERRCODE = '22023';
    END IF;
    v_folio := v_folio_txt::BIGINT;

    v_fecha_txt := public.fn_dte_texto(v_doc, 'Encabezado/IdDoc/FchEmis');
    BEGIN
        IF v_fecha_txt !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN
            RAISE EXCEPTION 'fecha';
        END IF;
        v_fecha := v_fecha_txt::DATE;
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'La fecha de emisión falta o no es válida.' USING ERRCODE = '22023';
    END;
    IF v_fecha IS NULL THEN
        RAISE EXCEPTION 'La fecha de emisión falta o no es válida.' USING ERRCODE = '22023';
    END IF;

    v_venc_txt := public.fn_dte_texto(v_doc, 'Encabezado/IdDoc/FchVenc');
    IF v_venc_txt IS NOT NULL THEN
        BEGIN
            IF v_venc_txt !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN
                RAISE EXCEPTION 'fecha';
            END IF;
            v_venc := v_venc_txt::DATE;
        EXCEPTION WHEN OTHERS THEN
            RAISE EXCEPTION 'La fecha de vencimiento no es válida.' USING ERRCODE = '22023';
        END;
    END IF;

    v_rut := public.fn_dte_texto(v_doc, 'Encabezado/Emisor/RUTEmisor');
    IF v_rut IS NULL THEN
        RAISE EXCEPTION 'No indica el RUT del emisor.' USING ERRCODE = '22023';
    END IF;
    v_rut_norm := public.fn_normalizar_rut(v_rut);
    IF v_rut_norm IS NULL THEN
        RAISE EXCEPTION 'El RUT del emisor (%) no es válido.', v_rut USING ERRCODE = '22023';
    END IF;

    v_neto   := CASE WHEN public.fn_dte_texto(v_doc, 'Encabezado/Totales/MntNeto') ~ '^-?[0-9]+$'
                     THEN public.fn_dte_texto(v_doc, 'Encabezado/Totales/MntNeto')::NUMERIC END;
    v_iva    := CASE WHEN public.fn_dte_texto(v_doc, 'Encabezado/Totales/IVA') ~ '^-?[0-9]+$'
                     THEN public.fn_dte_texto(v_doc, 'Encabezado/Totales/IVA')::NUMERIC END;
    v_total  := CASE WHEN public.fn_dte_texto(v_doc, 'Encabezado/Totales/MntTotal') ~ '^-?[0-9]+$'
                     THEN public.fn_dte_texto(v_doc, 'Encabezado/Totales/MntTotal')::NUMERIC END;
    v_exento := CASE WHEN public.fn_dte_texto(v_doc, 'Encabezado/Totales/MntExe') ~ '^-?[0-9]+$'
                     THEN public.fn_dte_texto(v_doc, 'Encabezado/Totales/MntExe')::NUMERIC ELSE 0 END;
    v_tasa   := CASE WHEN public.fn_dte_texto(v_doc, 'Encabezado/Totales/TasaIVA') ~ '^[0-9]+(\.[0-9]+)?$'
                     THEN public.fn_dte_texto(v_doc, 'Encabezado/Totales/TasaIVA')::NUMERIC END;
    IF v_neto IS NULL THEN
        RAISE EXCEPTION 'Falta el monto neto (MntNeto) o no es un número entero.' USING ERRCODE = '22023';
    END IF;
    IF v_iva IS NULL THEN
        RAISE EXCEPTION 'Falta el IVA o no es un número entero.' USING ERRCODE = '22023';
    END IF;
    IF v_total IS NULL THEN
        RAISE EXCEPTION 'Falta el monto total (MntTotal) o no es un número entero.' USING ERRCODE = '22023';
    END IF;

    v_otros_txt := (xpath('sum(' || c_documento || '/*[local-name()="Encabezado"]/*[local-name()="Totales"]'
                          || '/*[local-name()="ImptoReten"]/*[local-name()="MontoImp"])', v_doc))[1]::TEXT;
    IF v_otros_txt !~ '^-?[0-9]+(\.[0-9]+)?$' THEN
        RAISE EXCEPTION 'Los impuestos adicionales (ImptoReten) no son números válidos.' USING ERRCODE = '22023';
    END IF;
    v_otros := v_otros_txt::NUMERIC;

    IF v_neto + v_exento + v_iva + v_otros <> v_total THEN
        RAISE EXCEPTION 'Los totales no cuadran: neto, exento, IVA e impuestos suman %, pero el total informado es %.',
            v_neto + v_exento + v_iva + v_otros, v_total USING ERRCODE = '22023';
    END IF;

    v_incluye_iva := COALESCE(public.fn_dte_texto(v_doc, 'Encabezado/IdDoc/IndMntBruto') = '1', FALSE);
    v_forma_pago := public.fn_dte_texto(v_doc, 'Encabezado/IdDoc/FmaPago');
    v_orden_compra := NULLIF(btrim((xpath('string(' || c_documento
        || '/*[local-name()="Referencia"][*[local-name()="TpoDocRef"]="801"][1]/*[local-name()="FolioRef"])',
        v_doc))[1]::TEXT), '');

    -- ¿Ya fue ingresada? (H3.7) -------------------------------------------------------
    -- El candado serializa dos confirmaciones de la misma factura (doble clic o dos
    -- sesiones): la segunda espera y luego ve la primera. La restricción única es la
    -- última defensa (si dos solicitudes chocan igual, la restricción rechaza a la segunda).
    PERFORM pg_advisory_xact_lock(hashtext('factura_xml:' || v_rut_norm || ':33:' || v_folio));

    SELECT f.id, f.sucursal_id INTO v_existente, v_suc_existente
      FROM public.facturas_compra f
     WHERE f.rut_emisor_normalizado = v_rut_norm AND f.tipo_documento = 33 AND f.folio = v_folio;
    IF FOUND THEN
        -- H3.7 T07: se registra el intento y se devuelve el resultado. No se lanza error: un
        -- error deshace la transacción y el registro se perdería. No se guarda nada más.
        INSERT INTO public.intentos_factura_duplicada
            (usuario_id, sucursal_solicitada_id, rut_emisor_normalizado, tipo_documento, folio,
             factura_compra_id, sucursal_factura_id, xml_nombre, xml_sha256)
        VALUES
            (v_actor, p_sucursal_id, v_rut_norm, 33, v_folio,
             v_existente, v_suc_existente, left(p_xml_nombre, 255), encode(sha256(v_bytes), 'hex'))
        RETURNING id INTO v_intento;
        RETURN jsonb_build_object('ya_ingresada', TRUE, 'intento_id', v_intento);
    END IF;

    -- Proveedor por RUT; si no existe queda NULL (decidido el 16/10/2026).
    SELECT p.id INTO v_proveedor
      FROM public.proveedores p
     WHERE public.fn_normalizar_rut(p.rut) = v_rut_norm
     LIMIT 1;

    -- Cabeceras ------------------------------------------------------------------
    INSERT INTO public.facturas_compra
        (proveedor_id, sucursal_id, numero_factura, fecha_factura, monto_neto, monto_iva,
         monto_impuestos_especificos, monto_total, estado, origen,
         rut_emisor_normalizado, tipo_documento, folio)
    VALUES
        (v_proveedor, p_sucursal_id, v_folio::TEXT, v_fecha, v_neto, v_iva,
         v_otros, v_total, 'confirmada', 'xml',
         v_rut_norm, 33, v_folio)
    RETURNING id INTO v_factura;

    INSERT INTO public.facturas_xml_pendientes
        (sucursal_id, cargado_por, estado, tipo_documento, folio, rut_emisor, rut_emisor_normalizado,
         razon_social_emisor, rut_receptor, fecha_emision, fecha_vencimiento, forma_pago,
         orden_compra_referencia, monto_neto, monto_iva, tasa_iva, monto_total,
         xml_original, xml_nombre, xml_sha256, detalle_incluye_iva,
         factura_id, confirmado_por, confirmado_en)
    VALUES
        (p_sucursal_id, v_actor, 'confirmada', 33, v_folio, left(v_rut, 12), v_rut_norm,
         left(public.fn_dte_texto(v_doc, 'Encabezado/Emisor/RznSoc'), 150),
         left(public.fn_dte_texto(v_doc, 'Encabezado/Receptor/RUTRecep'), 12),
         v_fecha, v_venc,
         CASE WHEN v_forma_pago ~ '^[0-9]{1,4}$' THEN v_forma_pago::SMALLINT END,
         left(v_orden_compra, 60), v_neto, v_iva, v_tasa, v_total,
         v_bytes, left(p_xml_nombre, 255), encode(sha256(v_bytes), 'hex'), v_incluye_iva,
         v_factura, v_actor, now())
    RETURNING id INTO v_pendiente;

    -- Líneas -------------------------------------------------------------------------
    v_total_lineas := (xpath('count(' || c_documento || '/*[local-name()="Detalle"])', v_doc))[1]::TEXT::NUMERIC::INTEGER;
    IF v_total_lineas = 0 THEN
        RAISE EXCEPTION 'La factura no trae líneas de detalle.' USING ERRCODE = '22023';
    END IF;

    FOR v_pos IN 1..v_total_lineas LOOP
        v_nro_txt := public.fn_dte_texto(v_doc, 'NroLinDet', v_pos);
        v_nro := CASE WHEN v_nro_txt ~ '^[0-9]{1,9}$' THEN v_nro_txt::INTEGER ELSE v_pos END;
        IF v_nro = ANY (v_numeros) THEN
            RAISE EXCEPTION 'La factura repite el número de línea %.', v_nro USING ERRCODE = '22023';
        END IF;
        v_numeros := v_numeros || v_nro;

        v_desc := public.fn_dte_texto(v_doc, 'NmbItem', v_pos);
        v_codigo := public.fn_dte_texto(v_doc, 'CdgItem/VlrCodigo', v_pos);
        v_codigo_tipo := public.fn_dte_texto(v_doc, 'CdgItem/TpoCodigo', v_pos);
        v_qty_txt := public.fn_dte_texto(v_doc, 'QtyItem', v_pos);
        v_prc_txt := public.fn_dte_texto(v_doc, 'PrcItem', v_pos);
        v_monto_txt := public.fn_dte_texto(v_doc, 'MontoItem', v_pos);

        IF v_desc IS NULL THEN
            RAISE EXCEPTION 'Línea %: falta la descripción del artículo.', v_nro USING ERRCODE = '22023';
        END IF;
        IF v_qty_txt IS NULL OR v_qty_txt !~ '^[0-9]+(\.[0-9]+)?$' OR v_qty_txt::NUMERIC <= 0 THEN
            RAISE EXCEPTION 'Línea %: la cantidad falta o no es mayor que cero.', v_nro USING ERRCODE = '22023';
        END IF;
        IF v_prc_txt IS NULL OR v_prc_txt !~ '^[0-9]+(\.[0-9]+)?$' THEN
            RAISE EXCEPTION 'Línea %: falta el precio unitario.', v_nro USING ERRCODE = '22023';
        END IF;
        IF v_monto_txt IS NULL OR v_monto_txt !~ '^-?[0-9]+$' THEN
            RAISE EXCEPTION 'Línea %: falta el monto de la línea.', v_nro USING ERRCODE = '22023';
        END IF;
        v_qty := v_qty_txt::NUMERIC;
        v_prc := v_prc_txt::NUMERIC;
        v_monto := v_monto_txt::NUMERIC;

        -- Qué eligió el usuario para esta línea.
        SELECT count(*) INTO v_cuenta
          FROM jsonb_array_elements(p_lineas) e
         WHERE e->>'numero_linea' = v_nro::TEXT;
        IF v_cuenta > 1 THEN
            RAISE EXCEPTION 'La línea % aparece más de una vez en la asociación.', v_nro USING ERRCODE = '22023';
        END IF;
        SELECT e INTO v_asoc
          FROM jsonb_array_elements(p_lineas) e
         WHERE e->>'numero_linea' = v_nro::TEXT;

        v_ingrediente := CASE WHEN v_asoc->>'ingrediente_id' ~ '^[0-9]{1,9}$'
                              THEN (v_asoc->>'ingrediente_id')::INTEGER END;
        v_producto := CASE WHEN v_asoc->>'producto_id' ~ '^[0-9]{1,9}$'
                           THEN (v_asoc->>'producto_id')::INTEGER END;
        v_no_inventario := COALESCE(v_asoc->'no_corresponde_inventario' = 'true'::JSONB, FALSE);
        v_equivalencia := CASE WHEN jsonb_typeof(v_asoc->'unidades_por_presentacion') = 'number'
                               THEN (v_asoc->>'unidades_por_presentacion')::NUMERIC END;

        IF num_nonnulls(v_ingrediente, v_producto) + (CASE WHEN v_no_inventario THEN 1 ELSE 0 END) > 1 THEN
            RAISE EXCEPTION 'La línea % tiene más de una clasificación.', v_nro USING ERRCODE = '22023';
        END IF;

        IF v_asoc IS NULL OR (num_nonnulls(v_ingrediente, v_producto) = 0 AND NOT v_no_inventario) THEN
            v_sin_asociar := v_sin_asociar + 1;
            CONTINUE;
        END IF;

        IF v_no_inventario THEN
            INSERT INTO public.facturas_xml_pendientes_lineas
                (factura_xml_id, numero_linea, codigo_tipo, codigo_proveedor, descripcion,
                 cantidad, precio_unitario, monto, no_corresponde_inventario)
            VALUES
                (v_pendiente, v_nro, left(v_codigo_tipo, 20), left(v_codigo, 60), left(v_desc, 255),
                 v_qty, v_prc, v_monto, TRUE);
            v_lineas_otras := v_lineas_otras + 1;
            CONTINUE;
        END IF;

        IF v_equivalencia IS NULL OR v_equivalencia <= 0 OR v_equivalencia <> round(v_equivalencia, 3) THEN
            v_sin_equivalencia := v_sin_equivalencia + 1;
            CONTINUE;
        END IF;

        IF v_ingrediente IS NOT NULL THEN
            SELECT i.unidad_id INTO v_unidad
              FROM public.ingredientes i
             WHERE i.id = v_ingrediente AND i.activo;
            IF NOT FOUND THEN
                RAISE EXCEPTION 'Línea %: la materia prima elegida no existe o está inactiva.', v_nro
                    USING ERRCODE = '22023';
            END IF;
        ELSE
            IF NOT EXISTS (SELECT 1 FROM public.productos p WHERE p.id = v_producto AND p.activo) THEN
                RAISE EXCEPTION 'Línea %: el producto elegido no existe o está inactivo.', v_nro
                    USING ERRCODE = '22023';
            END IF;
            IF EXISTS (SELECT 1 FROM public.recetas r WHERE r.producto_id = v_producto) THEN
                RAISE EXCEPTION 'Línea %: el producto elegido tiene receta; su stock sale de sus ingredientes.', v_nro
                    USING ERRCODE = '22023';
            END IF;
            v_unidad := NULL;
        END IF;

        v_cantidad := round(v_qty * v_equivalencia, 3);
        IF v_cantidad <= 0 THEN
            RAISE EXCEPTION 'Línea %: la cantidad a ingresar es demasiado pequeña.', v_nro USING ERRCODE = '22023';
        END IF;

        INSERT INTO public.facturas_xml_pendientes_lineas
            (factura_xml_id, numero_linea, codigo_tipo, codigo_proveedor, descripcion,
             cantidad, precio_unitario, monto, ingrediente_id, producto_id, unidades_por_presentacion)
        VALUES
            (v_pendiente, v_nro, left(v_codigo_tipo, 20), left(v_codigo, 60), left(v_desc, 255),
             v_qty, v_prc, v_monto, v_ingrediente, v_producto, v_equivalencia);

        -- Costo neto de la línea; si los montos incluyen IVA, se le descuenta.
        v_costo := CASE WHEN v_incluye_iva
                        THEN round(v_monto / (1 + COALESCE(v_tasa, 19) / 100), 2)
                        ELSE v_monto END;
        v_precio := round(v_costo / v_cantidad, 2);

        -- El stock lo suma fn_aplicar_compra (AFTER INSERT), una sola vez por fila.
        INSERT INTO public.detalle_factura_compra
            (factura_id, ingrediente_id, producto_id, codigo_proveedor, unidades_por_presentacion,
             cantidad, unidad_id, precio_unitario, descuento_monto)
        VALUES
            (v_factura, v_ingrediente, v_producto, left(v_codigo, 30),
             CASE WHEN v_equivalencia = round(v_equivalencia, 2) AND v_equivalencia < 100000000
                  THEN v_equivalencia END,
             v_cantidad, v_unidad, v_precio,
             -- Diferencia de redondeo de precio_unitario (2 decimales): así subtotal_neto
             -- es exactamente el monto de la línea.
             round(v_cantidad * v_precio, 2) - v_costo);

        v_lineas_stock := v_lineas_stock + 1;
    END LOOP;

    IF v_sin_asociar > 0 THEN
        RAISE EXCEPTION 'Faltan asociar % línea(s): elige un artículo o márcalas como «No corresponde a inventario».',
            v_sin_asociar USING ERRCODE = '22023';
    END IF;
    IF v_sin_equivalencia > 0 THEN
        RAISE EXCEPTION 'Falta la equivalencia de % línea(s) asociadas a un artículo.', v_sin_equivalencia
            USING ERRCODE = '22023';
    END IF;
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_lineas) e
                WHERE NOT (e->>'numero_linea' ~ '^[0-9]{1,9}$'
                           AND (e->>'numero_linea')::INTEGER = ANY (v_numeros))) THEN
        RAISE EXCEPTION 'La asociación menciona líneas que no están en la factura.' USING ERRCODE = '22023';
    END IF;

    RETURN jsonb_build_object(
        'factura_compra_id', v_factura,
        'factura_xml_id', v_pendiente,
        'lineas_inventario', v_lineas_stock,
        'lineas_no_inventario', v_lineas_otras);
END;
$$;

-- Solo roles de inventario. Las funciones auxiliares no se publican como RPC.
REVOKE ALL ON FUNCTION public.fn_ingresar_factura_xml(integer, text, text, jsonb)
    FROM PUBLIC, web_anon, nury_cajero;
GRANT EXECUTE ON FUNCTION public.fn_ingresar_factura_xml(integer, text, text, jsonb)
    TO nury_admin, nury_bodeguero;

COMMIT;


-- #####################################################################
-- 25. database/migrations/20261020_versiones_receta.sql
-- #####################################################################

-- H2.5 T02 - Obtener la receta vigente y sus ingredientes al confirmar la venta,
-- identificando la versión utilizada.
--
-- Decisión (Sebastián, 2026-10-20): se guarda la receta actual de cada producto compuesto
-- como una versión, y cada vez que se edita la receta se crea una versión nueva.
--   - recetas sigue siendo la receta editable (el Maestro de Productos no cambia).
--   - Cada cambio en recetas (agregar, cambiar cantidad o quitar un insumo) crea una
--     versión nueva con la copia completa de los ingredientes. Una sentencia que cambia
--     varias filas crea una sola versión, y un cambio que deja la receta igual no crea
--     ninguna. Si se quitan todos los insumos queda una versión vacía: el producto pasa
--     a ser de reventa.
--   - Al insertar una línea de venta se guarda en detalle_venta.receta_version_id la
--     versión vigente del producto (NULL si no tiene receta) y fn_aplicar_venta descuenta
--     los ingredientes de esa versión. Así cada venta sabe con qué receta se hizo.
--
-- Contenido:
--   T01  tablas recetas_version y recetas_version_detalle
--   T02  fn_versionar_receta() + trigger en recetas
--   T03  versión 1 de las recetas que ya existen
--   T04  detalle_venta.receta_version_id + trigger que la completa
--   T05  fn_aplicar_venta descontando por la versión (reemplaza la de 0004)
--   T06  fn_versiones_receta(): historial que muestra el Maestro de Productos
--
-- Requiere: 0004_stock_producto_reventa.sql y 20261012_permisos_cajero.sql
-- (fn_usuario_actual_id, para registrar quién editó la receta).
--
-- ANTES DE APLICAR EN PRODUCCIÓN:
--   a) Confirmar que fn_aplicar_venta de producción es la de 0004 (T05 la reemplaza):
--        SELECT pg_get_functiondef('public.fn_aplicar_venta()'::regprocedure);
--   b) Correr database/tests/versiones_receta.sql en una base de pruebas y luego
--      20261020_versiones_receta.ENSAYO.sql (termina en ROLLBACK).
--   c) Después de aplicar: NOTIFY pgrst, 'reload schema';

BEGIN;

-- T01) Versiones de receta --------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.recetas_version (
    id            SERIAL PRIMARY KEY,
    producto_id   INTEGER NOT NULL REFERENCES public.productos(id),
    numero        INTEGER NOT NULL CHECK (numero > 0),
    vigente_desde TIMESTAMP NOT NULL DEFAULT now(),
    creada_por    INTEGER REFERENCES public.usuarios(id),   -- NULL: carga inicial o cambio sin sesión
    UNIQUE (producto_id, numero)
);

CREATE TABLE IF NOT EXISTS public.recetas_version_detalle (
    id                 SERIAL PRIMARY KEY,
    version_id         INTEGER NOT NULL REFERENCES public.recetas_version(id) ON DELETE CASCADE,
    ingrediente_id     INTEGER NOT NULL REFERENCES public.ingredientes(id),
    cantidad_necesaria NUMERIC(12,3) NOT NULL CHECK (cantidad_necesaria > 0),
    unidad_id          INTEGER NOT NULL REFERENCES public.unidades_medida(id),
    UNIQUE (version_id, ingrediente_id)
);

-- Lectura para administración (historial de recetas). Se escriben solo por trigger.
GRANT SELECT ON public.recetas_version, public.recetas_version_detalle TO nury_admin;

-- T02) Una versión nueva por cada cambio de la receta --------------------------
CREATE OR REPLACE FUNCTION public.fn_versionar_receta(p_producto_id INTEGER)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $function$
DECLARE
    v_ultima  public.recetas_version%ROWTYPE;
    v_version INTEGER;
BEGIN
    -- Ordena los cambios simultáneos de una misma receta. NO KEY UPDATE no bloquea las
    -- ventas (la FK de detalle_venta solo toma KEY SHARE sobre el producto).
    PERFORM 1 FROM public.productos WHERE id = p_producto_id FOR NO KEY UPDATE;
    IF NOT FOUND THEN
        RETURN;  -- el producto se está eliminando junto con su receta
    END IF;

    SELECT * INTO v_ultima
      FROM public.recetas_version
     WHERE producto_id = p_producto_id
     ORDER BY numero DESC
     LIMIT 1;

    IF FOUND THEN
        -- Sin cambios reales respecto de la última versión: no se crea otra.
        IF NOT EXISTS (
            (SELECT ingrediente_id, cantidad_necesaria, unidad_id
               FROM public.recetas WHERE producto_id = p_producto_id
             EXCEPT
             SELECT ingrediente_id, cantidad_necesaria, unidad_id
               FROM public.recetas_version_detalle WHERE version_id = v_ultima.id)
            UNION ALL
            (SELECT ingrediente_id, cantidad_necesaria, unidad_id
               FROM public.recetas_version_detalle WHERE version_id = v_ultima.id
             EXCEPT
             SELECT ingrediente_id, cantidad_necesaria, unidad_id
               FROM public.recetas WHERE producto_id = p_producto_id)
        ) THEN
            RETURN;
        END IF;
    ELSIF NOT EXISTS (SELECT 1 FROM public.recetas WHERE producto_id = p_producto_id) THEN
        RETURN;  -- nunca tuvo receta
    END IF;

    INSERT INTO public.recetas_version (producto_id, numero, creada_por)
    VALUES (p_producto_id, COALESCE(v_ultima.numero, 0) + 1, public.fn_usuario_actual_id())
    RETURNING id INTO v_version;

    INSERT INTO public.recetas_version_detalle (version_id, ingrediente_id, cantidad_necesaria, unidad_id)
    SELECT v_version, ingrediente_id, cantidad_necesaria, unidad_id
      FROM public.recetas
     WHERE producto_id = p_producto_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_versionar_receta(integer) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.fn_recetas_versionar()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $function$
BEGIN
    -- Los triggers AFTER ROW se ejecutan al terminar la sentencia y ya ven todas sus
    -- filas: la primera crea la versión y las siguientes la encuentran igual.
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        PERFORM public.fn_versionar_receta(NEW.producto_id);
    END IF;
    IF TG_OP = 'DELETE' OR (TG_OP = 'UPDATE' AND OLD.producto_id <> NEW.producto_id) THEN
        PERFORM public.fn_versionar_receta(OLD.producto_id);
    END IF;
    RETURN NULL;
END;
$function$;

DROP TRIGGER IF EXISTS trg_recetas_versionar ON public.recetas;
CREATE TRIGGER trg_recetas_versionar
    AFTER INSERT OR UPDATE OR DELETE ON public.recetas
    FOR EACH ROW EXECUTE FUNCTION public.fn_recetas_versionar();

-- T03) Las recetas actuales quedan como versión 1 -------------------------------
INSERT INTO public.recetas_version (producto_id, numero)
SELECT DISTINCT r.producto_id, 1
  FROM public.recetas r
 WHERE NOT EXISTS (SELECT 1 FROM public.recetas_version v WHERE v.producto_id = r.producto_id);

INSERT INTO public.recetas_version_detalle (version_id, ingrediente_id, cantidad_necesaria, unidad_id)
SELECT v.id, r.ingrediente_id, r.cantidad_necesaria, r.unidad_id
  FROM public.recetas_version v
  JOIN public.recetas r ON r.producto_id = v.producto_id
 WHERE v.numero = 1
   AND NOT EXISTS (SELECT 1 FROM public.recetas_version_detalle d WHERE d.version_id = v.id);

-- T04) Cada línea de venta guarda la versión con que se hizo --------------------
ALTER TABLE public.detalle_venta
    ADD COLUMN IF NOT EXISTS receta_version_id INTEGER REFERENCES public.recetas_version(id);

CREATE INDEX IF NOT EXISTS idx_detalle_venta_receta_version
    ON public.detalle_venta (receta_version_id)
    WHERE receta_version_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.fn_detalle_venta_receta_version()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $function$
DECLARE
    v_version INTEGER;
BEGIN
    -- La versión la decide la base, no quien registra la venta.
    SELECT v.id INTO v_version
      FROM public.recetas_version v
     WHERE v.producto_id = NEW.producto_id
     ORDER BY v.numero DESC
     LIMIT 1;

    -- Una versión vacía (se quitaron todos los insumos) significa "sin receta".
    IF v_version IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM public.recetas_version_detalle WHERE version_id = v_version) THEN
        v_version := NULL;
    END IF;

    NEW.receta_version_id := v_version;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_detalle_venta_receta_version ON public.detalle_venta;
CREATE TRIGGER trg_detalle_venta_receta_version
    BEFORE INSERT ON public.detalle_venta
    FOR EACH ROW EXECUTE FUNCTION public.fn_detalle_venta_receta_version();

-- T05) fn_aplicar_venta descuenta los ingredientes de esa versión ---------------
-- Igual a la de 0004 salvo: v_tiene_receta, la receta recorrida y el costo de la alerta
-- de margen salen de recetas_version_detalle de NEW.receta_version_id.
CREATE OR REPLACE FUNCTION public.fn_aplicar_venta() RETURNS TRIGGER AS $$
DECLARE
    v_sucursal_id  INTEGER;
    v_tiene_receta BOOLEAN;
    receta_row     RECORD;
    v_stock_previo NUMERIC(12,3);
    v_descuento    NUMERIC(12,3);
    v_nuevo_stock  NUMERIC(12,3);
    v_costo_receta NUMERIC(12,2);
BEGIN
    SELECT sucursal_id INTO v_sucursal_id FROM ventas WHERE id = NEW.venta_id;

    -- H2.5 T02: la versión de receta la fijó trg_detalle_venta_receta_version al insertar
    -- la línea; se descuentan exactamente sus ingredientes, aunque la receta cambie después.
    v_tiene_receta := NEW.receta_version_id IS NOT NULL;

    IF v_tiene_receta THEN
        FOR receta_row IN
            SELECT ingrediente_id, cantidad_necesaria
              FROM recetas_version_detalle
             WHERE version_id = NEW.receta_version_id
        LOOP
            v_descuento := receta_row.cantidad_necesaria * NEW.cantidad;

            INSERT INTO stock_sucursal (ingrediente_id, sucursal_id, stock_actual, stock_minimo)
            VALUES (receta_row.ingrediente_id, v_sucursal_id, 0, 0)
            ON CONFLICT (ingrediente_id, sucursal_id) DO NOTHING;

            SELECT stock_actual INTO v_stock_previo
              FROM stock_sucursal
             WHERE ingrediente_id = receta_row.ingrediente_id AND sucursal_id = v_sucursal_id
             FOR UPDATE;

            v_nuevo_stock := v_stock_previo - v_descuento;

            UPDATE stock_sucursal
               SET stock_actual = v_nuevo_stock,
                   actualizado_en = now()
             WHERE ingrediente_id = receta_row.ingrediente_id AND sucursal_id = v_sucursal_id;

            INSERT INTO movimientos_stock
                (ingrediente_id, sucursal_id, tipo_movimiento, cantidad, stock_resultante, referencia_tipo, referencia_id)
            VALUES
                (receta_row.ingrediente_id, v_sucursal_id, 'venta', -v_descuento, v_nuevo_stock, 'venta', NEW.venta_id);
        END LOOP;
    ELSE
        -- Producto de reventa: descuenta su propio stock en la sucursal de la venta.
        v_descuento := NEW.cantidad;

        INSERT INTO stock_producto_sucursal (producto_id, sucursal_id, stock_actual, stock_minimo)
        VALUES (NEW.producto_id, v_sucursal_id, 0, 0)
        ON CONFLICT (producto_id, sucursal_id) DO NOTHING;

        SELECT stock_actual INTO v_stock_previo
          FROM stock_producto_sucursal
         WHERE producto_id = NEW.producto_id AND sucursal_id = v_sucursal_id
         FOR UPDATE;

        v_nuevo_stock := v_stock_previo - v_descuento;

        UPDATE stock_producto_sucursal
           SET stock_actual = v_nuevo_stock,
               actualizado_en = now()
         WHERE producto_id = NEW.producto_id AND sucursal_id = v_sucursal_id;

        INSERT INTO movimientos_stock
            (producto_id, sucursal_id, tipo_movimiento, cantidad, stock_resultante, referencia_tipo, referencia_id)
        VALUES
            (NEW.producto_id, v_sucursal_id, 'venta', -v_descuento, v_nuevo_stock, 'venta', NEW.venta_id);
    END IF;

    -- Alerta de margen: si la línea trae promoción y el precio aplicado queda bajo el costo de receta, se registra (no bloquea)
    IF NEW.promocion_id IS NOT NULL THEN
        SELECT COALESCE(SUM(r.cantidad_necesaria * i.costo_unitario_promedio), 0)
          INTO v_costo_receta
          FROM recetas_version_detalle r JOIN ingredientes i ON i.id = r.ingrediente_id
         WHERE r.version_id = NEW.receta_version_id;

        IF NEW.precio_unitario < v_costo_receta THEN
            INSERT INTO alertas_margen (promocion_id, producto_id, costo_receta, precio_aplicado, venta_id)
            VALUES (NEW.promocion_id, NEW.producto_id, v_costo_receta, NEW.precio_unitario, NEW.venta_id);
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- T06) Historial para el Maestro de Productos ------------------------------------
-- Versiones de la receta de un producto, de la más nueva a la más antigua, con el
-- nombre de quien la editó y qué insumos se agregaron, quitaron o cambiaron respecto
-- de la anterior. Función aparte para no dar lectura sobre usuarios.
CREATE OR REPLACE FUNCTION public.fn_versiones_receta(p_producto_id INTEGER)
RETURNS TABLE (numero INTEGER, vigente_desde TIMESTAMP, creada_por VARCHAR, insumos INTEGER, cambios JSONB)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $function$
    WITH versiones AS (
        SELECT v.*, lag(v.id) OVER (ORDER BY v.numero) AS anterior_id
          FROM public.recetas_version v
         WHERE v.producto_id = p_producto_id
    )
    SELECT v.numero,
           v.vigente_desde,
           u.nombre::VARCHAR,
           (SELECT count(*)::INTEGER FROM public.recetas_version_detalle d WHERE d.version_id = v.id),
           -- Qué cambió respecto de la versión anterior (NULL en la primera):
           -- [{tipo: agregado|quitado|modificado, ingrediente, unidad, antes, despues}]
           CASE WHEN v.anterior_id IS NOT NULL THEN COALESCE((
               SELECT jsonb_agg(jsonb_build_object(
                          'tipo', c.tipo, 'ingrediente', i.nombre, 'unidad', um.abreviatura,
                          'antes', c.antes, 'despues', c.despues) ORDER BY i.nombre)
                 FROM (
                     SELECT COALESCE(n.ingrediente_id, a.ingrediente_id) AS ingrediente_id,
                            COALESCE(n.unidad_id, a.unidad_id) AS unidad_id,
                            CASE WHEN a.ingrediente_id IS NULL THEN 'agregado'
                                 WHEN n.ingrediente_id IS NULL THEN 'quitado'
                                 ELSE 'modificado' END AS tipo,
                            a.cantidad_necesaria AS antes,
                            n.cantidad_necesaria AS despues
                       FROM (SELECT * FROM public.recetas_version_detalle WHERE version_id = v.id) n
                       FULL JOIN (SELECT * FROM public.recetas_version_detalle WHERE version_id = v.anterior_id) a
                         ON a.ingrediente_id = n.ingrediente_id
                      WHERE a.ingrediente_id IS NULL OR n.ingrediente_id IS NULL
                         OR a.cantidad_necesaria <> n.cantidad_necesaria OR a.unidad_id <> n.unidad_id
                 ) c
                 JOIN public.ingredientes i ON i.id = c.ingrediente_id
                 LEFT JOIN public.unidades_medida um ON um.id = c.unidad_id
           ), '[]'::JSONB) END
      FROM versiones v
      LEFT JOIN public.usuarios u ON u.id = v.creada_por
     ORDER BY v.numero DESC;
$function$;

REVOKE ALL ON FUNCTION public.fn_versiones_receta(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_versiones_receta(integer) TO nury_admin, nury_cajero;

COMMIT;


-- #####################################################################
-- 26. database/migrations/20261021_historial_ajustes_bodeguero.sql
-- #####################################################################

-- Lectura del historial de ajustes y mermas para el bodeguero.
--
-- Hallazgo (2026-10-21): en Inventario > "Mermas y ajustes" el bodeguero recibía
-- "Tu rol no tiene permiso para ver el reporte de mermas". La API respondía 403
-- ("permission denied for table movimientos_stock") y, al pedir el responsable,
-- también fallaba usuarios. Con admin funcionaba.
--
-- Se concede lectura de movimientos_stock (el bodeguero ya ajusta stock con
-- fn_ajustar_stock) y solo id y nombre de usuarios, para mostrar quién hizo el
-- ajuste sin exponer credenciales, hash ni rol.
--
-- PENDIENTE DE APLICAR EN EL VPS. Es idempotente. Debe ejecutarla el dueño de las tablas.

BEGIN;

GRANT SELECT ON public.movimientos_stock TO nury_bodeguero;
GRANT SELECT (id, nombre) ON public.usuarios TO nury_bodeguero;

COMMIT;

NOTIFY pgrst, 'reload schema';


-- #####################################################################
-- 27. database/migrations/20261021_modelo_articulos.sql
-- #####################################################################

-- H3.3 T02 - Modelar artículos, tipo (producto normal o materia prima), unidad de medida,
-- estado activo y su relación con las existencias por sucursal.
--
-- Un ARTÍCULO es lo que se guarda en bodega y tiene stock propio. No es una tabla nueva:
-- se apoya en las dos que ya existen y las presenta con un solo formato.
--
--   tipo           tabla del artículo                      existencias por sucursal
--   materia_prima  ingredientes (unidad_id → unidades)     stock_sucursal
--   producto       productos SIN receta (siempre "un")     stock_producto_sucursal
--
-- Reglas del modelo:
--   - Un producto CON receta no es artículo: no tiene stock propio, descuenta sus
--     ingredientes (misma regla que fn_aplicar_venta, fn_aplicar_compra y fn_ajustar_stock).
--   - Los productos normales se cuentan siempre por unidad (decisión 2026-10-21: no se
--     venden por peso), por eso productos no tiene unidad_id.
--   - Desactivar = activo FALSE; un artículo con historial nunca se borra.
--   - La unidad de una materia prima no cambia si ya está en uso (recetas o movimientos):
--     no hay conversión de unidades (T03).
--
-- Contenido:
--   T01  v_articulos: catálogo de artículos (Catálogo de Inventario, H3.3 T01/T03/T04)
--   T02  v_existencias_articulos: existencias de cada artículo por sucursal
--   T03  la unidad de una materia prima en uso no se puede cambiar
--
-- Las vistas leen con los permisos de su dueño (no security_invoker): el bodeguero no
-- tiene lectura sobre recetas (verificado en producción el 2026-10-21) y la necesita solo
-- para saber si un producto tiene receta. La vista no expone ingredientes ni cantidades
-- de las recetas, y solo admin y bodeguero pueden consultarla.
--
-- ANTES DE APLICAR EN PRODUCCIÓN:
--   a) Correr database/tests/modelo_articulos.sql en una base de pruebas y luego
--      20261021_modelo_articulos.ENSAYO.sql (termina en ROLLBACK).
--   b) Después de aplicar: NOTIFY pgrst, 'reload schema';

BEGIN;

-- T01) Catálogo de artículos -------------------------------------------------------
CREATE OR REPLACE VIEW public.v_articulos AS
SELECT 'materia_prima'::VARCHAR(20)  AS tipo,
       i.id                          AS articulo_id,
       i.nombre,
       i.unidad_id,
       um.abreviatura                AS unidad,
       um.nombre                     AS unidad_nombre,
       i.codigo_barras,
       i.activo,
       i.creado_en
  FROM public.ingredientes i
  JOIN public.unidades_medida um ON um.id = i.unidad_id
UNION ALL
SELECT 'producto'::VARCHAR(20),
       p.id,
       p.nombre,
       NULL::INTEGER,
       'un'::VARCHAR(10),
       'Unidad'::VARCHAR(40),
       p.codigo_barras,
       p.activo,
       p.creado_en
  FROM public.productos p
 WHERE NOT EXISTS (SELECT 1 FROM public.recetas r WHERE r.producto_id = p.id);

COMMENT ON VIEW public.v_articulos IS
    'Artículos de bodega (H3.3 T02): materias primas (ingredientes) y productos normales (productos sin receta). Los productos se cuentan por unidad.';
COMMENT ON COLUMN public.v_articulos.tipo IS 'materia_prima | producto';
COMMENT ON COLUMN public.v_articulos.articulo_id IS 'ingredientes.id o productos.id según tipo';
COMMENT ON COLUMN public.v_articulos.unidad_id IS 'Unidad de la materia prima; NULL en productos (siempre "un")';

-- T02) Existencias de cada artículo por sucursal -----------------------------------
CREATE OR REPLACE VIEW public.v_existencias_articulos AS
SELECT 'materia_prima'::VARCHAR(20) AS tipo,
       s.ingrediente_id             AS articulo_id,
       i.nombre,
       um.abreviatura               AS unidad,
       i.activo,
       s.sucursal_id,
       su.nombre                    AS sucursal,
       s.stock_actual,
       s.stock_minimo,
       s.actualizado_en
  FROM public.stock_sucursal s
  JOIN public.ingredientes i ON i.id = s.ingrediente_id
  JOIN public.unidades_medida um ON um.id = i.unidad_id
  JOIN public.sucursales su ON su.id = s.sucursal_id
UNION ALL
SELECT 'producto'::VARCHAR(20),
       s.producto_id,
       p.nombre,
       'un'::VARCHAR(10),
       p.activo,
       s.sucursal_id,
       su.nombre,
       s.stock_actual,
       s.stock_minimo,
       s.actualizado_en
  FROM public.stock_producto_sucursal s
  JOIN public.productos p ON p.id = s.producto_id
  JOIN public.sucursales su ON su.id = s.sucursal_id
 WHERE NOT EXISTS (SELECT 1 FROM public.recetas r WHERE r.producto_id = s.producto_id);

COMMENT ON VIEW public.v_existencias_articulos IS
    'Existencias de cada artículo por sucursal (H3.3 T02). Una fila por artículo y sucursal que ya tiene stock registrado.';

-- Solo los roles de inventario.
REVOKE ALL ON public.v_articulos, public.v_existencias_articulos FROM PUBLIC;
GRANT SELECT ON public.v_articulos, public.v_existencias_articulos TO nury_admin, nury_bodeguero;

-- T03) Unidad fija de una materia prima en uso -------------------------------------
CREATE OR REPLACE FUNCTION public.fn_ingrediente_unidad_fija()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $function$
BEGIN
    IF NEW.unidad_id IS DISTINCT FROM OLD.unidad_id AND (
           EXISTS (SELECT 1 FROM public.recetas WHERE ingrediente_id = OLD.id)
        OR EXISTS (SELECT 1 FROM public.movimientos_stock WHERE ingrediente_id = OLD.id)
        OR EXISTS (SELECT 1 FROM public.stock_sucursal WHERE ingrediente_id = OLD.id AND stock_actual <> 0)
    ) THEN
        RAISE EXCEPTION 'No se puede cambiar la unidad de "%": ya se usa en recetas o tiene stock', OLD.nombre
            USING ERRCODE = '22023';
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_ingredientes_unidad_fija ON public.ingredientes;
CREATE TRIGGER trg_ingredientes_unidad_fija
    BEFORE UPDATE OF unidad_id ON public.ingredientes
    FOR EACH ROW EXECUTE FUNCTION public.fn_ingrediente_unidad_fija();

COMMIT;


-- #####################################################################
-- 28. database/migrations/20261021_permiso_recetas_bodeguero.sql
-- #####################################################################

-- Lectura mínima de recetas para el bodeguero.
--
-- Hallazgo (2026-10-21): el bodeguero no tenía ningún permiso sobre recetas, y tres
-- pantallas que usa consultan GET /recetas?select=producto_id para descartar los
-- productos con receta (no tienen stock propio): el panel de Inventario, el modal
-- "Ajustar stock" y la carga de facturas XML. Con admin funcionaban; al bodeguero le
-- fallaban completas.
--
-- Se concede solo la columna producto_id: el bodeguero puede saber qué productos tienen
-- receta, pero no sus ingredientes ni cantidades.
--
-- YA APLICADA EN PRODUCCIÓN el 2026-10-21 (verificado: producto_id = true,
-- cantidad_necesaria = false). Es idempotente: se puede volver a correr sin efecto.
-- Debe ejecutarla el dueño de la tabla recetas.

BEGIN;

GRANT SELECT (producto_id) ON public.recetas TO nury_bodeguero;

COMMIT;

NOTIFY pgrst, 'reload schema';


-- #####################################################################
-- 29. database/migrations/20261022_almuerzo_unico_por_dia.sql
-- #####################################################################

-- H2.13 T04 — Almuerzo de empleados: al menos un producto y un solo almuerzo
-- por empleado al día, informando el motivo del rechazo.
--
--   - Un almuerzo sin productos ya lo rechazaba fn_registrar_almuerzo_empleado
--     (T03): "El almuerzo no tiene productos". Se mantiene.
--   - Un empleado solo registra un almuerzo por fecha (en hora de Chile), sin
--     importar la sucursal ni quién lo registre. Lo asegura un índice único, así
--     que ni dos cajeros registrando a la vez pueden duplicarlo. El rechazo
--     explica quién, dónde y a qué hora se registró el almuerzo del día.
--
-- Contenido:
--   T01  índice único (empleado_id, fecha)
--   T02  fn_registrar_almuerzo_empleado con el control diario (reemplaza la de T03)
--
-- Requiere: 20261022_registrar_almuerzo_empleado.sql.
--
-- ANTES DE APLICAR EN PRODUCCIÓN:
--   a) Revisar que no haya almuerzos repetidos (si hay, T01 falla y no se aplica nada):
--        SELECT empleado_id, fecha, count(*) FROM almuerzos_empleado
--         GROUP BY 1, 2 HAVING count(*) > 1;
--   b) Correr database/tests/almuerzo_unico_por_dia.sql.
--   c) Después de aplicar: NOTIFY pgrst, 'reload schema';

BEGIN;

-- T01) Un almuerzo por empleado y día --------------------------------------------
-- Reemplaza al índice no único de 20261022_almuerzos_empleado.sql, que cubría las
-- mismas columnas para la consulta por empleado y periodo.
CREATE UNIQUE INDEX IF NOT EXISTS ux_almuerzos_empleado_empleado_fecha
    ON public.almuerzos_empleado(empleado_id, fecha);

DROP INDEX IF EXISTS public.idx_almuerzos_empleado_empleado_fecha;

-- T02) Registro con el control diario ------------------------------------------------
-- Igual a la de 20261022_registrar_almuerzo_empleado.sql, más el control de un almuerzo
-- por día antes de guardar (con el detalle del ya registrado) y, si otro registro entra
-- al mismo tiempo, la traducción del índice único al mismo motivo.
CREATE OR REPLACE FUNCTION public.fn_registrar_almuerzo_empleado(
    p_sucursal_id INTEGER,
    p_empleado_id INTEGER,
    p_items       JSONB
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $function$
DECLARE
    v_actor_id    INTEGER := public.fn_usuario_actual_id();
    v_actor       RECORD;
    v_fecha       DATE := (now() AT TIME ZONE 'America/Santiago')::date;
    v_empleado    TEXT;
    v_previo      RECORD;
    v_almuerzo_id INTEGER;
    item          JSONB;
    v_producto_id INTEGER;
    v_cantidad    NUMERIC;
    v_vistos      INTEGER[] := '{}';
    linea         RECORD;
BEGIN
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'La sesión no identifica a un usuario autorizado' USING ERRCODE = '42501';
    END IF;

    SELECT rol, sucursal_id INTO v_actor FROM public.usuarios WHERE id = v_actor_id;

    IF NOT EXISTS (SELECT 1 FROM public.sucursales WHERE id = p_sucursal_id AND activo) THEN
        RAISE EXCEPTION 'La sucursal no existe o está deshabilitada' USING ERRCODE = '22023';
    END IF;

    IF v_actor.rol = 'cajero' AND v_actor.sucursal_id IS DISTINCT FROM p_sucursal_id THEN
        RAISE EXCEPTION 'Solo puedes registrar almuerzos en tu sucursal' USING ERRCODE = '42501';
    END IF;

    IF p_empleado_id IS NULL THEN
        RAISE EXCEPTION 'Debes indicar el empleado que almuerza' USING ERRCODE = '22023';
    END IF;

    SELECT nombre INTO v_empleado FROM public.usuarios WHERE id = p_empleado_id AND activo;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'El empleado no existe o está deshabilitado' USING ERRCODE = '22023';
    END IF;

    IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'El almuerzo no tiene productos: agrega al menos uno' USING ERRCODE = '22023';
    END IF;

    -- Un almuerzo por día: se informa cuándo, dónde y quién registró el de hoy.
    SELECT a.creado_en, s.nombre AS sucursal, u.nombre AS cajero INTO v_previo
      FROM public.almuerzos_empleado a
      JOIN public.sucursales s ON s.id = a.sucursal_id
      JOIN public.usuarios u ON u.id = a.cajero_id
     WHERE a.empleado_id = p_empleado_id AND a.fecha = v_fecha;
    IF FOUND THEN
        RAISE EXCEPTION '% ya registró su almuerzo hoy (a las % en %, lo registró %). Solo se permite un almuerzo por día',
            v_empleado, to_char(v_previo.creado_en::timestamptz AT TIME ZONE 'America/Santiago', 'HH24:MI'),
            v_previo.sucursal, v_previo.cajero
            USING ERRCODE = '23505';
    END IF;

    BEGIN
        INSERT INTO public.almuerzos_empleado (sucursal_id, empleado_id, cajero_id, fecha)
        VALUES (p_sucursal_id, p_empleado_id, v_actor_id, v_fecha)
        RETURNING id INTO v_almuerzo_id;
    EXCEPTION
        WHEN unique_violation THEN
            -- Otro registro del mismo empleado entró justo antes que este.
            RAISE EXCEPTION '% ya registró su almuerzo hoy. Solo se permite un almuerzo por día', v_empleado
                USING ERRCODE = '23505';
    END;

    FOR item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        IF jsonb_typeof(item->'producto_id') <> 'number'
           OR (item->>'producto_id') !~ '^[0-9]{1,9}$' THEN
            RAISE EXCEPTION 'Producto no válido: %', item->'producto_id' USING ERRCODE = '22023';
        END IF;
        v_producto_id := (item->>'producto_id')::INTEGER;

        IF jsonb_typeof(item->'cantidad') <> 'number' OR (item->>'cantidad')::NUMERIC <= 0 THEN
            RAISE EXCEPTION 'La cantidad debe ser mayor que 0' USING ERRCODE = '22023';
        END IF;
        v_cantidad := (item->>'cantidad')::NUMERIC;
        -- Se consumen unidades del producto (un menú, una bebida): no hay fracciones.
        IF v_cantidad <> trunc(v_cantidad) THEN
            RAISE EXCEPTION 'La cantidad debe ser un número entero' USING ERRCODE = '22023';
        END IF;

        IF v_producto_id = ANY (v_vistos) THEN
            RAISE EXCEPTION 'El producto % está repetido en el almuerzo', v_producto_id USING ERRCODE = '22023';
        END IF;
        v_vistos := v_vistos || v_producto_id;

        IF NOT EXISTS (SELECT 1 FROM public.productos WHERE id = v_producto_id AND activo) THEN
            RAISE EXCEPTION 'Producto no encontrado o inactivo: %', v_producto_id USING ERRCODE = '22023';
        END IF;

        -- trg_almuerzos_empleado_detalle_receta_version completa receta_version_id.
        INSERT INTO public.almuerzos_empleado_detalle (almuerzo_id, producto_id, cantidad)
        VALUES (v_almuerzo_id, v_producto_id, v_cantidad)
        RETURNING producto_id, cantidad, receta_version_id INTO linea;

        PERFORM public.fn_descontar_stock_producto(
            linea.producto_id, p_sucursal_id, linea.cantidad, linea.receta_version_id,
            'consumo_interno', 'almuerzo_empleado', v_almuerzo_id);
    END LOOP;

    RETURN v_almuerzo_id;
END;
$function$;

COMMIT;

NOTIFY pgrst, 'reload schema';


-- #####################################################################
-- 30. database/migrations/20261022_almuerzos_empleado.sql
-- #####################################################################

-- H2.13 T02 — Almuerzo de empleados sin cobro: modelo del registro.
--
-- Contexto: el almuerzo diario de los empleados es consumo interno. No es una
-- venta: no tiene medio de pago ni total y no debe aparecer en ventas, caja ni
-- reportes de venta. Por eso se guarda en tablas propias, separadas de
-- `ventas` y `detalle_venta`.
--
--   almuerzos_empleado          cabecera: empleado, cajero, fecha y sucursal.
--   almuerzos_empleado_detalle  productos consumidos y sus cantidades.
--
-- Este script solo CREA tablas nuevas. No toca ventas ni stock: el registro
-- (con su descuento de stock) y la regla de un almuerzo por día se hacen en
-- las tareas siguientes de H2.13, mediante una función SECURITY DEFINER.
--
-- ANTES DE APLICAR EN PRODUCCIÓN:
--   a) Revisar el script completo con el responsable.
--   b) Ejecutarlo como dueño de `ventas` (las tablas nuevas quedan con ese dueño).
--   c) Después de aplicar: NOTIFY pgrst, 'reload schema';

BEGIN;

-- Cabecera del almuerzo --------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.almuerzos_empleado (
    id              SERIAL PRIMARY KEY,
    sucursal_id     INTEGER NOT NULL REFERENCES public.sucursales(id),
    empleado_id     INTEGER NOT NULL REFERENCES public.usuarios(id),   -- quién almuerza
    cajero_id       INTEGER NOT NULL REFERENCES public.usuarios(id),   -- quién lo registra
    -- Día del almuerzo en hora de Chile (no la del servidor): define el "un almuerzo
    -- por día" y los filtros por periodo.
    fecha           DATE NOT NULL DEFAULT (now() AT TIME ZONE 'America/Santiago')::date,
    creado_en       TIMESTAMP NOT NULL DEFAULT now()
);

-- Consultas del administrador por sucursal, empleado y periodo.
CREATE INDEX IF NOT EXISTS idx_almuerzos_empleado_sucursal_fecha
    ON public.almuerzos_empleado(sucursal_id, fecha);
CREATE INDEX IF NOT EXISTS idx_almuerzos_empleado_empleado_fecha
    ON public.almuerzos_empleado(empleado_id, fecha);

COMMENT ON TABLE public.almuerzos_empleado IS
    'Almuerzo diario de empleados sin cobro (H2.13). Consumo interno: no es una venta.';
COMMENT ON COLUMN public.almuerzos_empleado.empleado_id IS 'Empleado que almuerza.';
COMMENT ON COLUMN public.almuerzos_empleado.cajero_id IS 'Usuario que registra el almuerzo.';
COMMENT ON COLUMN public.almuerzos_empleado.fecha IS 'Día del almuerzo, en hora de Chile.';

-- Productos consumidos -----------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.almuerzos_empleado_detalle (
    id              SERIAL PRIMARY KEY,
    almuerzo_id     INTEGER NOT NULL REFERENCES public.almuerzos_empleado(id) ON DELETE CASCADE,
    producto_id     INTEGER NOT NULL REFERENCES public.productos(id),
    cantidad        NUMERIC(12,3) NOT NULL CHECK (cantidad > 0),   -- mismo tipo que detalle_venta
    UNIQUE (almuerzo_id, producto_id)                              -- un producto, una línea
);

CREATE INDEX IF NOT EXISTS idx_almuerzos_empleado_detalle_producto
    ON public.almuerzos_empleado_detalle(producto_id);

COMMENT ON TABLE public.almuerzos_empleado_detalle IS
    'Productos y cantidades de cada almuerzo de empleados (H2.13).';

-- Dueño y permisos ---------------------------------------------------------------
-- Mismo dueño que `ventas`, para que la función de registro (SECURITY DEFINER, con
-- ese dueño) pueda escribir. Nadie escribe directo: solo se concede lectura al
-- admin (consulta de almuerzos) y al cajero (revisar lo registrado en su turno).

DO $$
DECLARE
    v_owner TEXT;
    t       TEXT;
BEGIN
    SELECT pg_get_userbyid(relowner) INTO v_owner
      FROM pg_class WHERE oid = 'public.ventas'::regclass;

    FOREACH t IN ARRAY ARRAY['almuerzos_empleado', 'almuerzos_empleado_detalle'] LOOP
        EXECUTE format('ALTER TABLE public.%I OWNER TO %I', t, v_owner);
        EXECUTE format('ALTER SEQUENCE public.%I OWNER TO %I', t || '_id_seq', v_owner);
        EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC', t);
    END LOOP;
END $$;

REVOKE ALL ON public.almuerzos_empleado, public.almuerzos_empleado_detalle
    FROM web_anon, nury_cajero, nury_bodeguero;
GRANT SELECT ON public.almuerzos_empleado, public.almuerzos_empleado_detalle
    TO nury_admin, nury_cajero;

-- Lecturas que usa la pestaña «Almuerzo empleados» (H2.13 T01) -------------------
-- El cajero elige sucursal y ve si cada producto tiene receta. Igual que con el
-- bodeguero (20261021_permiso_recetas_bodeguero.sql), de recetas solo se concede
-- producto_id: no ve ingredientes ni cantidades. Ambos GRANT son idempotentes.

GRANT SELECT ON public.sucursales TO nury_cajero;
GRANT SELECT (producto_id) ON public.recetas TO nury_cajero;

COMMIT;

NOTIFY pgrst, 'reload schema';


-- #####################################################################
-- 31. database/migrations/20261022_movimientos_timestamptz.sql
-- #####################################################################

-- Zona horaria para movimientos de stock (Pedido 10).
--
-- Contexto (2026-10-22):
-- movimientos_stock.creado_en fue definido originalmente como TIMESTAMP (sin zona horaria)
-- y almacenaba en UTC. Al enviarse por PostgREST sin offset/zona explícita, requería
-- conversión manual en el cliente.
-- Se migra a TIMESTAMPTZ asumiendo que los registros existentes están en UTC, y se fija
-- DEFAULT now() para asegurar que todo evento guarde zona horaria explícita.
--
-- APLICADA EN PRODUCCIÓN/VPS el 2026-10-22 por dev_patricio (con rol nury_admin).
-- Requiere ser ejecutada por el dueño de las tablas (nury_admin).

SET ROLE nury_admin;

BEGIN;

ALTER TABLE public.movimientos_stock
    ALTER COLUMN creado_en TYPE TIMESTAMPTZ USING creado_en AT TIME ZONE 'UTC',
    ALTER COLUMN creado_en SET DEFAULT now();

COMMIT;

NOTIFY pgrst, 'reload schema';

RESET ROLE;


-- #####################################################################
-- 32. database/migrations/20261022_registrar_almuerzo_empleado.sql
-- #####################################################################

-- H2.13 T03 — Almuerzo de empleados sin cobro: registro con descuento de stock.
--
-- fn_registrar_almuerzo_empleado guarda el almuerzo (cabecera y productos) y
-- descuenta el stock de la sucursal en una sola transacción: si algo falla,
-- no queda ni el almuerzo ni ningún descuento.
--
-- Reutiliza el mismo descuento que la venta (H3.2 y H2.5). Para no copiarlo,
-- el descuento por producto sale de fn_aplicar_venta a una función propia,
-- fn_descontar_stock_producto, que usan las dos:
--   - Producto con receta  -> descuenta los ingredientes de la versión de
--                             receta vigente (H2.5), guardada en la línea.
--   - Producto sin receta  -> descuenta las unidades de su stock propio (H3.2).
-- Igual que en la venta, el stock puede quedar negativo (no se bloquea).
--
-- Los movimientos del almuerzo quedan como consumo interno:
--   tipo_movimiento = 'consumo_interno', referencia_tipo = 'almuerzo_empleado',
--   referencia_id = id del almuerzo. No son 'venta', así que no los toman la
--   anulación de ventas ni el aviso de stock insuficiente de la venta.
--
-- Contenido:
--   T01  tipo de movimiento 'consumo_interno'
--   T02  fn_descontar_stock_producto (descuento compartido)
--   T03  fn_aplicar_venta usando el descuento compartido (mismo resultado)
--   T04  versión de receta en cada línea del almuerzo
--   T05  fn_registrar_almuerzo_empleado
--
-- Requiere: 20261022_almuerzos_empleado.sql, 20261020_versiones_receta.sql,
-- 0007_reponer_stock_anulacion_venta.sql y 20261012_permisos_cajero.sql.
--
-- ANTES DE APLICAR EN PRODUCCIÓN:
--   a) Confirmar que fn_aplicar_venta es la de 20261020_versiones_receta.sql (T03 la
--      reemplaza; solo cambia que el descuento se hace con la función compartida):
--        SELECT pg_get_functiondef('public.fn_aplicar_venta()'::regprocedure);
--   b) Confirmar el CHECK actual del tipo de movimiento (T01 lo reemplaza):
--        SELECT conname, pg_get_constraintdef(oid) FROM pg_constraint
--         WHERE conrelid = 'public.movimientos_stock'::regclass AND contype = 'c';
--   c) Correr database/tests/registrar_almuerzo_empleado.sql y las pruebas de venta.
--   d) Después de aplicar: NOTIFY pgrst, 'reload schema';

BEGIN;

-- T01) Nuevo tipo de movimiento ------------------------------------------------
-- Se reemplaza el CHECK que lista los tipos, igual que en 0007.
DO $$
DECLARE
    v_con TEXT;
BEGIN
    FOR v_con IN
        SELECT conname FROM pg_constraint
         WHERE conrelid = 'public.movimientos_stock'::regclass
           AND contype = 'c'
           AND pg_get_constraintdef(oid) ILIKE '%tipo_movimiento%'
    LOOP
        EXECUTE format('ALTER TABLE public.movimientos_stock DROP CONSTRAINT %I', v_con);
    END LOOP;
END $$;

ALTER TABLE public.movimientos_stock
    ADD CONSTRAINT movimientos_stock_tipo_movimiento_check
    CHECK (tipo_movimiento IN ('compra', 'venta', 'ajuste', 'merma', 'anulacion_venta', 'consumo_interno'));

-- T02) Descuento de stock de un producto ----------------------------------------
-- El mismo bloque que tenía fn_aplicar_venta (20261020_versiones_receta.sql), con el
-- tipo y la referencia del movimiento como parámetros. Interna: no se expone en PostgREST.
CREATE OR REPLACE FUNCTION public.fn_descontar_stock_producto(
    p_producto_id       INTEGER,
    p_sucursal_id       INTEGER,
    p_cantidad          NUMERIC,
    p_receta_version_id INTEGER,   -- NULL = producto de reventa
    p_tipo_movimiento   TEXT,
    p_referencia_tipo   TEXT,
    p_referencia_id     INTEGER
)
RETURNS VOID
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $function$
DECLARE
    receta_row     RECORD;
    v_stock_previo NUMERIC(12,3);
    v_descuento    NUMERIC(12,3);
    v_nuevo_stock  NUMERIC(12,3);
BEGIN
    IF p_receta_version_id IS NOT NULL THEN
        -- H2.5: se descuentan exactamente los ingredientes de esa versión de receta.
        FOR receta_row IN
            SELECT ingrediente_id, cantidad_necesaria
              FROM recetas_version_detalle
             WHERE version_id = p_receta_version_id
        LOOP
            v_descuento := receta_row.cantidad_necesaria * p_cantidad;

            INSERT INTO stock_sucursal (ingrediente_id, sucursal_id, stock_actual, stock_minimo)
            VALUES (receta_row.ingrediente_id, p_sucursal_id, 0, 0)
            ON CONFLICT (ingrediente_id, sucursal_id) DO NOTHING;

            SELECT stock_actual INTO v_stock_previo
              FROM stock_sucursal
             WHERE ingrediente_id = receta_row.ingrediente_id AND sucursal_id = p_sucursal_id
             FOR UPDATE;

            v_nuevo_stock := v_stock_previo - v_descuento;

            UPDATE stock_sucursal
               SET stock_actual = v_nuevo_stock,
                   actualizado_en = now()
             WHERE ingrediente_id = receta_row.ingrediente_id AND sucursal_id = p_sucursal_id;

            INSERT INTO movimientos_stock
                (ingrediente_id, sucursal_id, tipo_movimiento, cantidad, stock_resultante, referencia_tipo, referencia_id)
            VALUES
                (receta_row.ingrediente_id, p_sucursal_id, p_tipo_movimiento, -v_descuento, v_nuevo_stock,
                 p_referencia_tipo, p_referencia_id);
        END LOOP;
    ELSE
        -- H3.2: producto de reventa, descuenta su propio stock en la sucursal.
        v_descuento := p_cantidad;

        INSERT INTO stock_producto_sucursal (producto_id, sucursal_id, stock_actual, stock_minimo)
        VALUES (p_producto_id, p_sucursal_id, 0, 0)
        ON CONFLICT (producto_id, sucursal_id) DO NOTHING;

        SELECT stock_actual INTO v_stock_previo
          FROM stock_producto_sucursal
         WHERE producto_id = p_producto_id AND sucursal_id = p_sucursal_id
         FOR UPDATE;

        v_nuevo_stock := v_stock_previo - v_descuento;

        UPDATE stock_producto_sucursal
           SET stock_actual = v_nuevo_stock,
               actualizado_en = now()
         WHERE producto_id = p_producto_id AND sucursal_id = p_sucursal_id;

        INSERT INTO movimientos_stock
            (producto_id, sucursal_id, tipo_movimiento, cantidad, stock_resultante, referencia_tipo, referencia_id)
        VALUES
            (p_producto_id, p_sucursal_id, p_tipo_movimiento, -v_descuento, v_nuevo_stock,
             p_referencia_tipo, p_referencia_id);
    END IF;
END;
$function$;

-- T03) fn_aplicar_venta con el descuento compartido -----------------------------
-- Igual a la de 20261020_versiones_receta.sql: el descuento ahora lo hace
-- fn_descontar_stock_producto con tipo y referencia 'venta'. La alerta de margen no cambia.
CREATE OR REPLACE FUNCTION public.fn_aplicar_venta() RETURNS TRIGGER AS $$
DECLARE
    v_sucursal_id  INTEGER;
    v_costo_receta NUMERIC(12,2);
BEGIN
    SELECT sucursal_id INTO v_sucursal_id FROM ventas WHERE id = NEW.venta_id;

    -- H2.5 T02: la versión de receta la fijó trg_detalle_venta_receta_version al insertar
    -- la línea; se descuentan exactamente sus ingredientes, aunque la receta cambie después.
    PERFORM fn_descontar_stock_producto(
        NEW.producto_id, v_sucursal_id, NEW.cantidad, NEW.receta_version_id,
        'venta', 'venta', NEW.venta_id);

    -- Alerta de margen: si la línea trae promoción y el precio aplicado queda bajo el costo de receta, se registra (no bloquea)
    IF NEW.promocion_id IS NOT NULL THEN
        SELECT COALESCE(SUM(r.cantidad_necesaria * i.costo_unitario_promedio), 0)
          INTO v_costo_receta
          FROM recetas_version_detalle r JOIN ingredientes i ON i.id = r.ingrediente_id
         WHERE r.version_id = NEW.receta_version_id;

        IF NEW.precio_unitario < v_costo_receta THEN
            INSERT INTO alertas_margen (promocion_id, producto_id, costo_receta, precio_aplicado, venta_id)
            VALUES (NEW.promocion_id, NEW.producto_id, v_costo_receta, NEW.precio_unitario, NEW.venta_id);
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- T04) Cada línea del almuerzo guarda la versión de receta con que se descontó --
-- Se reutiliza el trigger de detalle_venta (20261020): decide la versión vigente del
-- producto, o NULL si no tiene receta.
-- Sin FK a recetas_version: crearla exige permiso REFERENCES sobre esa tabla, que es de
-- otro dueño. El valor lo pone siempre el trigger leyendo recetas_version, y las
-- versiones no se borran, así que la referencia queda válida igual.
ALTER TABLE public.almuerzos_empleado_detalle
    ADD COLUMN IF NOT EXISTS receta_version_id INTEGER;

COMMENT ON COLUMN public.almuerzos_empleado_detalle.receta_version_id IS
    'Versión de receta (recetas_version.id) con que se descontó el stock; NULL si es de reventa.';

DROP TRIGGER IF EXISTS trg_almuerzos_empleado_detalle_receta_version ON public.almuerzos_empleado_detalle;
CREATE TRIGGER trg_almuerzos_empleado_detalle_receta_version
    BEFORE INSERT ON public.almuerzos_empleado_detalle
    FOR EACH ROW EXECUTE FUNCTION public.fn_detalle_venta_receta_version();

-- T05) Registro del almuerzo -------------------------------------------------------
-- p_items: [{"producto_id": 12, "cantidad": 1}, ...]. Quien registra (cajero_id) es el
-- usuario de la sesión. Un cajero solo registra en su sucursal; el admin, en cualquiera.
-- No pide medio de pago ni turno abierto: no es una venta y no pasa por caja.
CREATE OR REPLACE FUNCTION public.fn_registrar_almuerzo_empleado(
    p_sucursal_id INTEGER,
    p_empleado_id INTEGER,
    p_items       JSONB
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $function$
DECLARE
    v_actor_id    INTEGER := public.fn_usuario_actual_id();
    v_actor       RECORD;
    v_almuerzo_id INTEGER;
    item          JSONB;
    v_producto_id INTEGER;
    v_cantidad    NUMERIC;
    v_vistos      INTEGER[] := '{}';
    linea         RECORD;
BEGIN
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'La sesión no identifica a un usuario autorizado' USING ERRCODE = '42501';
    END IF;

    SELECT rol, sucursal_id INTO v_actor FROM public.usuarios WHERE id = v_actor_id;

    IF NOT EXISTS (SELECT 1 FROM public.sucursales WHERE id = p_sucursal_id AND activo) THEN
        RAISE EXCEPTION 'La sucursal no existe o está deshabilitada' USING ERRCODE = '22023';
    END IF;

    IF v_actor.rol = 'cajero' AND v_actor.sucursal_id IS DISTINCT FROM p_sucursal_id THEN
        RAISE EXCEPTION 'Solo puedes registrar almuerzos en tu sucursal' USING ERRCODE = '42501';
    END IF;

    IF p_empleado_id IS NULL THEN
        RAISE EXCEPTION 'Debes indicar el empleado que almuerza' USING ERRCODE = '22023';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.usuarios WHERE id = p_empleado_id AND activo) THEN
        RAISE EXCEPTION 'El empleado no existe o está deshabilitado' USING ERRCODE = '22023';
    END IF;

    IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'El almuerzo no tiene productos' USING ERRCODE = '22023';
    END IF;

    INSERT INTO public.almuerzos_empleado (sucursal_id, empleado_id, cajero_id)
    VALUES (p_sucursal_id, p_empleado_id, v_actor_id)
    RETURNING id INTO v_almuerzo_id;

    FOR item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        IF jsonb_typeof(item->'producto_id') <> 'number'
           OR (item->>'producto_id') !~ '^[0-9]{1,9}$' THEN
            RAISE EXCEPTION 'Producto no válido: %', item->'producto_id' USING ERRCODE = '22023';
        END IF;
        v_producto_id := (item->>'producto_id')::INTEGER;

        IF jsonb_typeof(item->'cantidad') <> 'number' OR (item->>'cantidad')::NUMERIC <= 0 THEN
            RAISE EXCEPTION 'La cantidad debe ser mayor que 0' USING ERRCODE = '22023';
        END IF;
        v_cantidad := (item->>'cantidad')::NUMERIC;
        -- Se consumen unidades del producto (un menú, una bebida): no hay fracciones.
        IF v_cantidad <> trunc(v_cantidad) THEN
            RAISE EXCEPTION 'La cantidad debe ser un número entero' USING ERRCODE = '22023';
        END IF;

        IF v_producto_id = ANY (v_vistos) THEN
            RAISE EXCEPTION 'El producto % está repetido en el almuerzo', v_producto_id USING ERRCODE = '22023';
        END IF;
        v_vistos := v_vistos || v_producto_id;

        IF NOT EXISTS (SELECT 1 FROM public.productos WHERE id = v_producto_id AND activo) THEN
            RAISE EXCEPTION 'Producto no encontrado o inactivo: %', v_producto_id USING ERRCODE = '22023';
        END IF;

        -- trg_almuerzos_empleado_detalle_receta_version completa receta_version_id.
        INSERT INTO public.almuerzos_empleado_detalle (almuerzo_id, producto_id, cantidad)
        VALUES (v_almuerzo_id, v_producto_id, v_cantidad)
        RETURNING producto_id, cantidad, receta_version_id INTO linea;

        PERFORM public.fn_descontar_stock_producto(
            linea.producto_id, p_sucursal_id, linea.cantidad, linea.receta_version_id,
            'consumo_interno', 'almuerzo_empleado', v_almuerzo_id);
    END LOOP;

    RETURN v_almuerzo_id;
END;
$function$;

-- Dueño y permisos ---------------------------------------------------------------
-- Mismo dueño que `ventas` (escribe almuerzos y stock). Solo el registro se expone, y
-- solo a admin y cajero; el descuento compartido no se llama directo desde PostgREST.
DO $$
DECLARE
    v_owner TEXT;
BEGIN
    SELECT pg_get_userbyid(relowner) INTO v_owner
      FROM pg_class WHERE oid = 'public.ventas'::regclass;

    EXECUTE format('ALTER FUNCTION public.fn_descontar_stock_producto(integer, integer, numeric, integer, text, text, integer) OWNER TO %I', v_owner);
    EXECUTE format('ALTER FUNCTION public.fn_registrar_almuerzo_empleado(integer, integer, jsonb) OWNER TO %I', v_owner);
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.fn_descontar_stock_producto(integer, integer, numeric, integer, text, text, integer) TO %I', v_owner);
END $$;

REVOKE ALL ON FUNCTION public.fn_descontar_stock_producto(integer, integer, numeric, integer, text, text, integer)
    FROM PUBLIC, web_anon, nury_cajero, nury_bodeguero;
REVOKE ALL ON FUNCTION public.fn_registrar_almuerzo_empleado(integer, integer, jsonb)
    FROM PUBLIC, web_anon, nury_bodeguero;
GRANT EXECUTE ON FUNCTION public.fn_registrar_almuerzo_empleado(integer, integer, jsonb)
    TO nury_admin, nury_cajero;

COMMIT;

NOTIFY pgrst, 'reload schema';


-- #####################################################################
-- 33. database/migrations/20261022_stock_minimo_bodeguero.sql
-- #####################################################################

-- Mínimo de stock no negativo y permiso de edición para el bodeguero (Pedidos 4 y 6).
--
-- Contexto (2026-10-22):
-- 1. Pedido 4: El frontend ya validaba que stock_minimo fuera >= 0; se agrega la
--    restricción formal CHECK en stock_sucursal y stock_producto_sucursal.
-- 2. Pedido 6: El equipo confirmó que el rol nury_bodeguero debe tener la facultad
--    de editar los mínimos de stock desde el panel de Inventario (evitando el error 403).
--    Siguiendo el principio de menor privilegio, se otorga UPDATE únicamente sobre la
--    columna stock_minimo, sin permitir modificar stock_actual ni columnas de auditoría.
--
-- APLICADA EN PRODUCCIÓN/VPS el 2026-10-22 por dev_patricio (con rol nury_admin).
-- Requiere ser ejecutada por el dueño de las tablas (nury_admin).

SET ROLE nury_admin;

BEGIN;

-- Restricción de no negatividad para mínimos de stock
ALTER TABLE public.stock_sucursal
    DROP CONSTRAINT IF EXISTS stock_minimo_no_negativo,
    ADD CONSTRAINT stock_minimo_no_negativo CHECK (stock_minimo >= 0);

ALTER TABLE public.stock_producto_sucursal
    DROP CONSTRAINT IF EXISTS stock_producto_minimo_no_negativo,
    ADD CONSTRAINT stock_producto_minimo_no_negativo CHECK (stock_minimo >= 0);

-- Permiso de actualización exclusivo para la columna stock_minimo
GRANT UPDATE (stock_minimo) ON public.stock_sucursal TO nury_bodeguero;
GRANT UPDATE (stock_minimo) ON public.stock_producto_sucursal TO nury_bodeguero;

COMMIT;

NOTIFY pgrst, 'reload schema';

RESET ROLE;


-- #####################################################################
-- 34. database/migrations/20261023_unidad_fija_ingrediente.sql
-- #####################################################################

-- H3.3 - La unidad de medida queda asociada permanentemente a la materia prima.
--
-- Criterio de aceptación: "La unidad de medida definida queda asociada permanentemente
-- al insumo y se usa como base para todos los cálculos de recetas y descuentos de stock."
--
-- 20261021_modelo_articulos.sql solo impedía cambiarla cuando el ingrediente ya estaba en
-- uso (recetas, movimientos o stock). La pantalla nunca la cambia al editar, pero por la
-- API todavía se podía cambiar la de un ingrediente sin uso. Esta migración reemplaza la
-- función del trigger trg_ingredientes_unidad_fija para que el cambio se rechace siempre.
-- Si se eligió mal la unidad al crear, se desactiva ese ingrediente y se crea otro.
--
-- ANTES DE APLICAR EN PRODUCCIÓN:
--   a) Correr database/tests/unidad_fija_ingrediente.sql en una base de pruebas y luego
--      20261023_unidad_fija_ingrediente.ENSAYO.sql (termina en ROLLBACK).
--   b) No requiere NOTIFY pgrst: no cambia la API.

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_ingrediente_unidad_fija()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $function$
BEGIN
    IF NEW.unidad_id IS DISTINCT FROM OLD.unidad_id THEN
        RAISE EXCEPTION 'La unidad de "%" no se puede cambiar: queda fija desde que se crea la materia prima', OLD.nombre
            USING ERRCODE = '22023';
    END IF;
    RETURN NEW;
END;
$function$;

COMMIT;


-- #####################################################################
-- 35. database/migrations/20261023_unidad_lamina.sql
-- #####################################################################

-- Unidad "Lámina" para materias primas que se cuentan por lámina (queso o jamón
-- laminado, por ejemplo). Criterio de H3.3: "unidad de medida (gramos, litros,
-- unidades, láminas, etc.)".
--
-- YA APLICADA EN PRODUCCIÓN el 2026-10-23 (INSERT 0 1). Idempotente: nombre y
-- abreviatura son UNIQUE, así que volver a correrla no hace nada.

BEGIN;

INSERT INTO public.unidades_medida (nombre, abreviatura) VALUES ('Lámina', 'lám')
ON CONFLICT DO NOTHING;

COMMIT;


-- #####################################################################
-- 36. database/migrations/20261024_estado_stock.sql
-- #####################################################################

-- H3.5 T04 - Regla compartida para los estados agotado, crítico y estable por sucursal.
--
-- Problema: la única consulta de "bajo stock" de la base era v_ingredientes_bajo_stock,
-- que solo marcaba stock_actual < stock_minimo. No distinguía un artículo agotado de uno
-- que solo está bajo el mínimo y no incluía los productos de reventa. Ninguna pantalla
-- la usa (revisado con grep en src/ y database/ el 2026-10-24).
--
-- Regla (la misma de calcularEstadoStock en inventario.model.ts):
--   agotado  stock_actual <= 0  (incluye el stock negativo que dejan las ventas)
--   crítico  stock_actual > 0 y menor que stock_minimo
--   estable  stock_actual > 0 e igual o mayor que stock_minimo
--
-- Contenido:
--   T01  fn_estado_stock: la regla en un solo lugar de la base
--   T02  v_estado_stock: estado de cada artículo activo por sucursal
--   T03  se elimina v_ingredientes_bajo_stock, reemplazada por v_estado_stock
--
-- Requiere: 20261021_modelo_articulos.sql (v_existencias_articulos).
--
-- ANTES DE APLICAR EN PRODUCCIÓN:
--   a) Correr database/tests/estado_stock.sql (crea todo, lo prueba y termina en ROLLBACK).
--   b) Esta migración ya termina con NOTIFY pgrst, 'reload schema'.
--
-- Requiere ser ejecutada por el dueño de las tablas (nury_admin), como las del 22-10.

SET ROLE nury_admin;

BEGIN;

-- T01) La regla -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_estado_stock(p_stock_actual NUMERIC, p_stock_minimo NUMERIC)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $function$
    SELECT CASE
        WHEN p_stock_actual <= 0           THEN 'agotado'
        WHEN p_stock_actual < p_stock_minimo THEN 'critico'
        ELSE 'estable'
    END;
$function$;

COMMENT ON FUNCTION public.fn_estado_stock(NUMERIC, NUMERIC) IS
    'H3.5 T04: agotado si stock <= 0; crítico si es positivo y menor que el mínimo; estable en otro caso.';

-- T02) Estado de cada artículo por sucursal --------------------------------------
-- Se apoya en v_existencias_articulos (materias primas y productos sin receta).
-- security_invoker: quien consulta necesita permiso sobre v_existencias_articulos,
-- que hoy tienen solo admin y bodeguero.
CREATE OR REPLACE VIEW public.v_estado_stock
WITH (security_invoker = true) AS
SELECT e.tipo,
       e.articulo_id,
       e.nombre,
       e.unidad,
       e.sucursal_id,
       e.sucursal,
       e.stock_actual,
       e.stock_minimo,
       public.fn_estado_stock(e.stock_actual, e.stock_minimo) AS estado,
       GREATEST(e.stock_minimo - e.stock_actual, 0)           AS cantidad_a_reponer
  FROM public.v_existencias_articulos e
 WHERE e.activo;

COMMENT ON VIEW public.v_estado_stock IS
    'H3.5 T04: estado (agotado, critico, estable) de cada artículo activo por sucursal. Reemplaza a v_ingredientes_bajo_stock.';

REVOKE ALL ON public.v_estado_stock FROM PUBLIC;
GRANT SELECT ON public.v_estado_stock TO nury_admin, nury_bodeguero;

-- T03) Consulta anterior -----------------------------------------------------------
-- Para la lista de reposición: SELECT * FROM v_estado_stock WHERE estado <> 'estable'.
DROP VIEW IF EXISTS public.v_ingredientes_bajo_stock;

COMMIT;

NOTIFY pgrst, 'reload schema';

RESET ROLE;


-- #####################################################################
-- 37. database/migrations/20261025_catalogo_materias_primas_bodeguero.sql
-- #####################################################################

-- H3.3 T03 - El bodeguero crea, edita y activa o desactiva materias primas desde el Catálogo.
--
-- Hallazgo (2026-10-25): nury_bodeguero solo tenía SELECT sobre ingredientes, sin INSERT,
-- UPDATE ni uso de la secuencia del id. Por eso al bodeguero le fallaba guardar en la
-- pantalla antigua de Ingredientes y le fallaría en el Catálogo de Inventario. Con admin
-- funcionaba.
--
-- Se conceden solo las columnas que la app envía:
--   - INSERT: nombre, unidad_id, categoria_id, codigo_barras (activo, costo y fechas
--     quedan con su valor por defecto).
--   - UPDATE: nombre, codigo_barras, activo y categoria_id (esta última la sigue enviando
--     la pantalla antigua de Ingredientes hasta que se retire en H3.3 T04).
-- Nunca unidad_id (queda fija: trg_ingredientes_unidad_fija) ni costo_unitario_promedio
-- (lo calcula el ingreso de facturas). Sin DELETE: las materias primas se desactivan.
--
-- Productos de reventa: el bodeguero NO recibe permisos nuevos. Activarlos o desactivarlos
-- los saca o devuelve a la venta en el POS, y eso queda para admin (Maestro de Productos).
--
-- ANTES DE APLICAR EN PRODUCCIÓN: correr 20261025_catalogo_materias_primas_bodeguero.ENSAYO.sql
-- (termina en ROLLBACK). Idempotente. Debe ejecutarla el dueño de la tabla ingredientes.

BEGIN;

GRANT INSERT (nombre, unidad_id, categoria_id, codigo_barras) ON public.ingredientes TO nury_bodeguero;
GRANT UPDATE (nombre, codigo_barras, activo, categoria_id) ON public.ingredientes TO nury_bodeguero;
GRANT USAGE ON SEQUENCE public.ingredientes_id_seq TO nury_bodeguero;

COMMIT;

NOTIFY pgrst, 'reload schema';


-- #####################################################################
-- 38. database/migrations/20261026_movimientos_articulos.sql
-- #####################################################################

-- H3.2 T01 - Relación entre ventas y movimientos de inventario.
--
-- Cada venta ya deja sus movimientos en movimientos_stock (fn_aplicar_venta, 0004; la
-- anulación los repone, 0007) con la venta (referencia_tipo/referencia_id), el artículo
-- (ingrediente_id o producto_id), la cantidad, la fecha (creado_en) y la sucursal. Lo que
-- faltaba era verlo junto y con el catálogo de H3.3: la unidad no es columna del kardex
-- (se deduce del artículo, y desde H3.3 queda fija) y el nombre del artículo había que
-- cruzarlo a mano.
--
-- v_movimientos_articulos: una fila por movimiento con tipo, venta, artículo (de
-- v_articulos), cantidad, unidad, stock resultante, fecha y sucursal. Solo lectura, sin
-- cambios en tablas ni en cómo se registran las ventas.
--
-- Un producto que vendió como reventa y después recibió receta sale de v_articulos (ya no
-- se guarda en bodega), pero sus movimientos antiguos siguen visibles: se completa el
-- nombre desde productos y la unidad es "un".
--
-- Permisos: SELECT para admin y bodeguero, igual que v_articulos. La vista corre con los
-- permisos de su dueño (como v_articulos), así el bodeguero no necesita leer las tablas.
--
-- ANTES DE APLICAR EN PRODUCCIÓN: correr 20261026_movimientos_articulos.ENSAYO.sql (termina
-- en ROLLBACK) y la prueba database/tests/movimientos_articulos.sql en una base de pruebas.

BEGIN;

CREATE OR REPLACE VIEW public.v_movimientos_articulos AS
SELECT m.id                                            AS movimiento_id,
       m.tipo_movimiento,
       CASE WHEN m.referencia_tipo = 'venta' THEN m.referencia_id END AS venta_id,
       m.referencia_tipo,
       m.referencia_id,
       CASE WHEN m.ingrediente_id IS NOT NULL THEN 'materia_prima' ELSE 'producto' END::VARCHAR(20)
                                                       AS tipo_articulo,
       COALESCE(m.ingrediente_id, m.producto_id)       AS articulo_id,
       COALESCE(a.nombre, p.nombre)                    AS articulo,
       COALESCE(a.unidad, 'un')::VARCHAR(10)           AS unidad,
       m.cantidad,
       m.stock_resultante,
       m.sucursal_id,
       s.nombre                                        AS sucursal,
       m.creado_en                                     AS fecha,
       m.nota
  FROM public.movimientos_stock m
  LEFT JOIN public.v_articulos a
         ON (a.tipo = 'materia_prima' AND a.articulo_id = m.ingrediente_id)
         OR (a.tipo = 'producto'      AND a.articulo_id = m.producto_id)
  LEFT JOIN public.productos p ON p.id = m.producto_id
  JOIN public.sucursales s ON s.id = m.sucursal_id;

COMMENT ON VIEW public.v_movimientos_articulos IS
    'Kardex con el catálogo de H3.3 (H3.2 T01): venta, artículo, cantidad, unidad, fecha y sucursal de cada movimiento.';
COMMENT ON COLUMN public.v_movimientos_articulos.venta_id IS 'Venta que originó el movimiento (venta o anulacion_venta); NULL en compras y ajustes';
COMMENT ON COLUMN public.v_movimientos_articulos.unidad IS 'Unidad del artículo (fija desde H3.3); "un" en productos';

REVOKE ALL ON public.v_movimientos_articulos FROM PUBLIC;
GRANT SELECT ON public.v_movimientos_articulos TO nury_admin, nury_bodeguero;

COMMIT;

NOTIFY pgrst, 'reload schema';


-- #####################################################################
-- 39. database/migrations/20261026_venta_idempotente.sql
-- #####################################################################

-- H2.5 T05 - Venta idempotente: un reintento del POS no duplica la venta ni el descuento.
--
-- Problema: si la base guarda la venta (y descuenta el stock) pero la respuesta no llega
-- al POS (corte de red o los 15 s de espera), el carrito sigue lleno y el cajero vuelve a
-- cobrar: quedaban dos ventas y el stock descontado dos veces.
--
-- Solución, sin modificar fn_registrar_venta (la mantienen otros integrantes):
--   - ventas_idempotencia: una fila por clave (UUID que genera el POS por venta) con la
--     venta que produjo y el cajero.
--   - fn_registrar_venta_idempotente(p_clave, ...mismos parámetros...): bloquea la clave
--     durante la transacción (pg_advisory_xact_lock, así dos reintentos simultáneos se
--     esperan), y si ya existe devuelve la venta original sin volver a registrar nada. Si
--     no existe, llama a fn_registrar_venta tal cual y guarda la clave en la MISMA
--     transacción: si la venta falla, la clave tampoco queda y el reintento vuelve a
--     intentar.
--   - Una clave de otro cajero se rechaza (no se devuelve una venta ajena).
--
-- El descuento de inventario sigue siendo el de siempre (fn_aplicar_venta, trigger de
-- detalle_venta), dentro de la misma transacción de la venta.
--
-- ANTES DE APLICAR EN PRODUCCIÓN: correr 20261026_venta_idempotente.ENSAYO.sql (termina en
-- ROLLBACK) y la prueba database/tests/venta_idempotente.sql en una base de pruebas.

BEGIN;

CREATE TABLE IF NOT EXISTS public.ventas_idempotencia (
    clave      UUID PRIMARY KEY,
    venta_id   INTEGER NOT NULL UNIQUE REFERENCES public.ventas(id),
    cajero_id  INTEGER REFERENCES public.usuarios(id),
    creado_en  TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.ventas_idempotencia IS
    'Clave única por venta enviada por el POS (H2.5 T05): un reintento con la misma clave devuelve la venta original.';

-- Solo la usa la función (SECURITY DEFINER); los roles de la app no la leen ni escriben.
REVOKE ALL ON public.ventas_idempotencia FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.fn_registrar_venta_idempotente(
    p_clave UUID,
    p_sucursal_id INTEGER,
    p_cajero_id INTEGER,
    p_medio_pago CHARACTER VARYING,
    p_items JSONB,
    p_tipo_venta CHARACTER VARYING DEFAULT 'normal',
    p_empleado_id INTEGER DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $function$
DECLARE
    v_existente public.ventas_idempotencia%ROWTYPE;
    v_venta_id  INTEGER;
BEGIN
    IF p_clave IS NULL THEN
        RAISE EXCEPTION 'Falta la clave única de la venta' USING ERRCODE = '22023';
    END IF;

    -- Dos envíos simultáneos de la misma venta: el segundo espera al primero.
    PERFORM pg_advisory_xact_lock(hashtextextended(p_clave::text, 0));

    SELECT * INTO v_existente FROM public.ventas_idempotencia WHERE clave = p_clave;
    IF FOUND THEN
        IF v_existente.cajero_id IS DISTINCT FROM p_cajero_id THEN
            RAISE EXCEPTION 'La clave de esta venta pertenece a otro cajero' USING ERRCODE = '42501';
        END IF;
        RETURN v_existente.venta_id;  -- reintento: la venta ya quedó registrada
    END IF;

    v_venta_id := public.fn_registrar_venta(
        p_sucursal_id, p_cajero_id, p_medio_pago, p_items, p_tipo_venta, p_empleado_id);

    INSERT INTO public.ventas_idempotencia (clave, venta_id, cajero_id)
    VALUES (p_clave, v_venta_id, p_cajero_id);

    RETURN v_venta_id;
END;
$function$;

COMMENT ON FUNCTION public.fn_registrar_venta_idempotente(uuid, integer, integer, character varying, jsonb, character varying, integer) IS
    'Registra la venta una sola vez por clave (H2.5 T05). Mismos parámetros que fn_registrar_venta más p_clave.';

-- Mismos roles que usan fn_registrar_venta desde la app.
REVOKE ALL ON FUNCTION public.fn_registrar_venta_idempotente(uuid, integer, integer, character varying, jsonb, character varying, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_registrar_venta_idempotente(uuid, integer, integer, character varying, jsonb, character varying, integer)
    TO nury_admin, nury_cajero;

COMMIT;

NOTIFY pgrst, 'reload schema';


-- #####################################################################
-- 40. database/migrations/20261027_detalle_venta_una_vez.sql
-- #####################################################################

-- H3.2 T03 - Los consumos de la venta (receta H2.5 y stock propio H3.2) se aplican una sola
-- vez por venta.
--
-- El descuento ya es un único proceso: el trigger fn_aplicar_venta corre una vez por línea de
-- detalle_venta, dentro de la transacción de fn_registrar_venta, y descuenta ingredientes
-- (producto con receta) o el stock propio (producto sin receta). Los reintentos del POS no
-- duplican gracias a fn_registrar_venta_idempotente (H2.5 T05).
--
-- Faltaba: el trigger solo actúa al INSERTAR. Con permisos de admin por la API se podía
--   - agregar una línea a una venta ya registrada o anulada → se descontaba otra vez;
--   - cambiar el producto o la cantidad de una línea → el stock no se ajustaba;
--   - borrar una línea → el stock no se devolvía.
--
-- trg_ventas_en_curso (AFTER INSERT en ventas): marca la venta como "en curso" en una variable
-- local de la transacción (set_config(..., true)), que desaparece al terminarla.
-- trg_detalle_venta_una_vez (BEFORE INSERT/UPDATE/DELETE en detalle_venta):
--   - INSERT solo mientras la venta está en curso, es decir, en la misma transacción en que se
--     creó (dentro de fn_registrar_venta), y nunca en una venta anulada.
--   - UPDATE de venta_id, producto_id o cantidad: rechazado.
--   - DELETE: rechazado, salvo cuando se borra la venta completa (ON DELETE CASCADE).
-- Para corregir una venta se anula (repone el stock exacto, 0007) y se registra de nuevo.
--
-- ANTES DE APLICAR EN PRODUCCIÓN: correr 20261027_detalle_venta_una_vez.ENSAYO.sql (termina
-- en ROLLBACK) y la prueba database/tests/detalle_venta_una_vez.sql.

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_ventas_en_curso()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $function$
BEGIN
    PERFORM set_config('nury.venta_en_curso_' || NEW.id, 'si', true);
    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_ventas_en_curso() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_ventas_en_curso ON public.ventas;
CREATE TRIGGER trg_ventas_en_curso
    AFTER INSERT ON public.ventas
    FOR EACH ROW EXECUTE FUNCTION public.fn_ventas_en_curso();

CREATE OR REPLACE FUNCTION public.fn_detalle_venta_una_vez()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $function$
DECLARE
    v_venta public.ventas%ROWTYPE;
BEGIN
    IF TG_OP = 'INSERT' THEN
        SELECT * INTO v_venta FROM public.ventas WHERE id = NEW.venta_id;
        IF NOT FOUND THEN
            RETURN NEW;  -- la llave foránea informa el error
        END IF;
        IF v_venta.anulada THEN
            RAISE EXCEPTION 'La venta #% está anulada: no se le pueden agregar productos', NEW.venta_id
                USING ERRCODE = '22023';
        END IF;
        -- La marca la deja trg_ventas_en_curso y solo vive en la transacción que creó la venta.
        IF current_setting('nury.venta_en_curso_' || NEW.venta_id, true) IS DISTINCT FROM 'si' THEN
            RAISE EXCEPTION 'La venta #% ya está registrada: sus productos solo se agregan al registrarla', NEW.venta_id
                USING ERRCODE = '22023';
        END IF;
        RETURN NEW;
    END IF;

    IF TG_OP = 'UPDATE' THEN
        IF NEW.venta_id IS DISTINCT FROM OLD.venta_id
           OR NEW.producto_id IS DISTINCT FROM OLD.producto_id
           OR NEW.cantidad IS DISTINCT FROM OLD.cantidad THEN
            RAISE EXCEPTION 'No se puede cambiar el producto ni la cantidad de una venta registrada: anúlala y regístrala de nuevo'
                USING ERRCODE = '22023';
        END IF;
        RETURN NEW;
    END IF;

    -- DELETE: solo como parte de borrar la venta completa (la venta ya no existe).
    IF EXISTS (SELECT 1 FROM public.ventas WHERE id = OLD.venta_id) THEN
        RAISE EXCEPTION 'No se pueden quitar productos de una venta registrada: anúlala y regístrala de nuevo'
            USING ERRCODE = '22023';
    END IF;
    RETURN OLD;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_detalle_venta_una_vez() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_detalle_venta_una_vez ON public.detalle_venta;
CREATE TRIGGER trg_detalle_venta_una_vez
    BEFORE INSERT OR UPDATE OR DELETE ON public.detalle_venta
    FOR EACH ROW EXECUTE FUNCTION public.fn_detalle_venta_una_vez();

COMMIT;


-- #####################################################################
-- 41. database/migrations/20261027_nombres_unicos_normalizados.sql
-- #####################################################################

-- H3.3 T05 - Validaciones de campos obligatorios y duplicados (ignorando mayúsculas y
-- espacios) en ingredientes y productos: nombre y código de barras.
--
-- Antes: UNIQUE (nombre) y UNIQUE (codigo_barras) distinguían mayúsculas y espacios, así que
-- por la API se podían crear "Harina", "harina" y "Harina  " como artículos distintos, o dos
-- productos con "ABC123" y "abc 123"; y un nombre de solo espacios pasaba el NOT NULL.
--
--   - fn_nombre_normalizado(texto): minúsculas, sin espacios en los extremos y con los
--     espacios internos repetidos reducidos a uno. IMMUTABLE para poder indexarla.
--   - ux_ingredientes_nombre_normalizado y ux_productos_nombre_normalizado: índices únicos
--     sobre ese valor. Un duplicado da 23505 → PostgREST 409 (la app muestra "Ya existe...").
--   - fn_codigo_normalizado(texto): código de barras en mayúsculas y sin ningún espacio.
--   - ux_ingredientes_codigo_normalizado y ux_productos_codigo_normalizado: índices únicos
--     parciales (solo filas con código).
--   - fn_limpiar_nombre_y_codigo (BEFORE INSERT/UPDATE OF nombre, codigo_barras): guarda el
--     nombre sin espacios en los extremos ni repetidos y el código sin espacios (vacío → NULL),
--     y rechaza un nombre vacío (22023).
--   - CHECK nombre no vacío en las dos tablas.
--
-- El tercer criterio (bloquear el cambio de unidad) ya se cumple de forma más estricta:
-- trg_ingredientes_unidad_fija lo rechaza siempre (20261023_unidad_fija_ingrediente.sql).
--
-- ANTES DE APLICAR EN PRODUCCIÓN: correr 20261027_nombres_unicos_normalizados.ENSAYO.sql
-- (termina en ROLLBACK). Si muestra duplicados, hay que resolverlos antes (renombrar o
-- desactivar y renombrar), porque el índice único no se puede crear con ellos.
-- Debe ejecutarla el dueño de las tablas ingredientes y productos.

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_nombre_normalizado(p_nombre TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $function$
    SELECT lower(regexp_replace(btrim(p_nombre), '\s+', ' ', 'g'));
$function$;

COMMENT ON FUNCTION public.fn_nombre_normalizado(text) IS
    'Nombre para comparar duplicados (H3.3 T05): minúsculas, sin espacios en los extremos ni repetidos.';

CREATE OR REPLACE FUNCTION public.fn_codigo_normalizado(p_codigo TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $function$
    SELECT upper(regexp_replace(p_codigo, '\s', '', 'g'));
$function$;

COMMENT ON FUNCTION public.fn_codigo_normalizado(text) IS
    'Código de barras para comparar duplicados (H3.3 T05): mayúsculas y sin espacios.';

CREATE OR REPLACE FUNCTION public.fn_limpiar_nombre_y_codigo()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $function$
BEGIN
    NEW.nombre := regexp_replace(btrim(NEW.nombre), '\s+', ' ', 'g');
    IF NEW.nombre = '' THEN
        RAISE EXCEPTION 'El nombre es obligatorio' USING ERRCODE = '22023';
    END IF;
    NEW.codigo_barras := NULLIF(regexp_replace(NEW.codigo_barras, '\s', '', 'g'), '');
    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_limpiar_nombre_y_codigo() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_ingredientes_limpiar_nombre ON public.ingredientes;
CREATE TRIGGER trg_ingredientes_limpiar_nombre
    BEFORE INSERT OR UPDATE OF nombre, codigo_barras ON public.ingredientes
    FOR EACH ROW EXECUTE FUNCTION public.fn_limpiar_nombre_y_codigo();

DROP TRIGGER IF EXISTS trg_productos_limpiar_nombre ON public.productos;
CREATE TRIGGER trg_productos_limpiar_nombre
    BEFORE INSERT OR UPDATE OF nombre, codigo_barras ON public.productos
    FOR EACH ROW EXECUTE FUNCTION public.fn_limpiar_nombre_y_codigo();

ALTER TABLE public.ingredientes DROP CONSTRAINT IF EXISTS ingredientes_nombre_no_vacio;
ALTER TABLE public.ingredientes ADD CONSTRAINT ingredientes_nombre_no_vacio CHECK (btrim(nombre) <> '');
ALTER TABLE public.productos DROP CONSTRAINT IF EXISTS productos_nombre_no_vacio;
ALTER TABLE public.productos ADD CONSTRAINT productos_nombre_no_vacio CHECK (btrim(nombre) <> '');

CREATE UNIQUE INDEX IF NOT EXISTS ux_ingredientes_nombre_normalizado
    ON public.ingredientes (public.fn_nombre_normalizado(nombre));
CREATE UNIQUE INDEX IF NOT EXISTS ux_productos_nombre_normalizado
    ON public.productos (public.fn_nombre_normalizado(nombre));

CREATE UNIQUE INDEX IF NOT EXISTS ux_ingredientes_codigo_normalizado
    ON public.ingredientes (public.fn_codigo_normalizado(codigo_barras))
    WHERE codigo_barras IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_productos_codigo_normalizado
    ON public.productos (public.fn_codigo_normalizado(codigo_barras))
    WHERE codigo_barras IS NOT NULL;

COMMIT;


-- #####################################################################
-- 42. database/migrations/20261027_receta_ingrediente_activo.sql
-- #####################################################################

-- H3.3 T07 - No se puede agregar un ingrediente inactivo a una receta.
--
-- Desactivar un artículo no borra nada: sus recetas, movimientos y stock se conservan. Lo que
-- no se permite es usarlo en asociaciones NUEVAS. La venta (fn_registrar_venta) y el ingreso
-- de facturas (fn_ingresar_factura_xml) ya rechazaban artículos inactivos; faltaban las
-- recetas: la pantalla solo ofrece ingredientes activos, pero por la API se podía agregar uno
-- inactivo.
--
-- trg_recetas_ingrediente_activo (BEFORE INSERT o UPDATE OF ingrediente_id): rechaza un
-- ingrediente inactivo. Las recetas que ya lo tienen siguen igual y se puede seguir editando
-- su cantidad o quitarlo.
--
-- ANTES DE APLICAR EN PRODUCCIÓN: correr 20261027_receta_ingrediente_activo.ENSAYO.sql
-- (termina en ROLLBACK) y la prueba database/tests/receta_ingrediente_activo.sql.

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_recetas_ingrediente_activo()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $function$
DECLARE
    v_nombre TEXT;
BEGIN
    IF TG_OP = 'UPDATE' AND NEW.ingrediente_id = OLD.ingrediente_id THEN
        RETURN NEW;
    END IF;

    SELECT nombre INTO v_nombre
      FROM public.ingredientes
     WHERE id = NEW.ingrediente_id AND NOT activo;

    IF FOUND THEN
        RAISE EXCEPTION '"%" está inactivo: no se puede agregar a una receta', v_nombre
            USING ERRCODE = '22023';
    END IF;
    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_recetas_ingrediente_activo() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_recetas_ingrediente_activo ON public.recetas;
CREATE TRIGGER trg_recetas_ingrediente_activo
    BEFORE INSERT OR UPDATE OF ingrediente_id ON public.recetas
    FOR EACH ROW EXECUTE FUNCTION public.fn_recetas_ingrediente_activo();

COMMIT;


-- #####################################################################
-- 43. database/migrations/20261027_receta_unidad_base.sql
-- #####################################################################

-- H2.5 T01 - Reglas de cálculo del consumo por receta: la receta usa la unidad base del
-- ingrediente.
--
-- Reglas (documentadas en docs/reglas-descuento-inventario.md):
--   1. Consumo de cada insumo = recetas.cantidad_necesaria × detalle_venta.cantidad
--      (fn_aplicar_venta, 0004). Ingredientes compartidos: cada línea descuenta lo suyo.
--   2. La cantidad de la receta está en la UNIDAD BASE del ingrediente (ingredientes.unidad_id,
--      fija desde H3.3). No hay conversión de unidades al vender.
--   3. Productos sin receta: descuentan su propio stock por unidad (H3.2, stock_producto_sucursal).
--   4. Saldo negativo permitido: la venta nunca se bloquea por falta de stock (H2.5 T04 avisa).
--
-- Lo que faltaba (regla 2): recetas.unidad_id es una columna propia y fn_aplicar_venta la
-- ignora. La pantalla siempre guarda la unidad del ingrediente, pero por la API se podía
-- guardar otra (p. ej. "g" para un ingrediente en "kg") y la venta descontaba mal.
--
-- trg_recetas_unidad_base (BEFORE INSERT/UPDATE): si unidad_id viene vacía, la completa
-- con la del ingrediente; si viene distinta, rechaza el cambio. Verificado en producción el
-- 2026-10-26: ninguna receta tenía hoy una unidad distinta a la de su ingrediente.
--
-- ANTES DE APLICAR EN PRODUCCIÓN: correr 20261027_receta_unidad_base.ENSAYO.sql (termina en
-- ROLLBACK) y la prueba database/tests/reglas_consumo_receta.sql en una base de pruebas.

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_recetas_unidad_base()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $function$
DECLARE
    v_unidad     INTEGER;
    v_nombre     TEXT;
    v_abrev_base TEXT;
BEGIN
    SELECT i.unidad_id, i.nombre, um.abreviatura
      INTO v_unidad, v_nombre, v_abrev_base
      FROM public.ingredientes i
      JOIN public.unidades_medida um ON um.id = i.unidad_id
     WHERE i.id = NEW.ingrediente_id;

    IF NOT FOUND THEN
        RETURN NEW;  -- la llave foránea de ingrediente_id informa el error
    END IF;

    IF NEW.unidad_id IS NULL THEN
        NEW.unidad_id := v_unidad;
    ELSIF NEW.unidad_id <> v_unidad THEN
        RAISE EXCEPTION 'La receta debe usar la unidad base de "%" (%): no hay conversión de unidades al vender',
            v_nombre, v_abrev_base
            USING ERRCODE = '22023';
    END IF;
    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_recetas_unidad_base() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_recetas_unidad_base ON public.recetas;
CREATE TRIGGER trg_recetas_unidad_base
    BEFORE INSERT OR UPDATE OF unidad_id, ingrediente_id ON public.recetas
    FOR EACH ROW EXECUTE FUNCTION public.fn_recetas_unidad_base();

COMMENT ON COLUMN public.recetas.unidad_id IS
    'Siempre la unidad base del ingrediente (trg_recetas_unidad_base, H2.5 T01). cantidad_necesaria está en esa unidad.';

COMMIT;


-- #####################################################################
-- 44. database/migrations/20261027_venta_concurrente.sql
-- #####################################################################

-- H3.2 T05 - Ventas simultáneas sin perder cantidades, descontando solo en la sucursal de la
-- venta.
--
-- Ya se cumplía:
--   - Sin pérdidas: fn_aplicar_venta (y compra, ajuste y anulación) bloquea la fila de stock
--     con SELECT ... FOR UPDATE antes de calcular y escribir el saldo. Una segunda venta del
--     mismo ítem espera a la primera y parte del saldo ya descontado.
--   - Sucursal: el descuento usa ventas.sucursal_id, y fn_registrar_venta exige que el cajero
--     tenga turno abierto en esa sucursal.
--
-- Faltaba: cada línea bloquea sus filas en el orden en que llegan. Dos ventas simultáneas con
-- los mismos ingredientes en orden distinto (sándwich+tostada y tostada+sándwich) pueden
-- quedar esperando una a la otra; PostgreSQL corta una con "deadlock detected" y el cajero ve
-- un error.
--
-- fn_registrar_venta_idempotente ahora, después de la revisión de la clave y antes de llamar a
-- fn_registrar_venta, crea (si faltan) y bloquea TODAS las filas de stock que la venta va a
-- tocar en la sucursal de la venta, siempre en el mismo orden: primero ingredientes por id,
-- luego productos por id. Así las ventas simultáneas se ordenan en fila en vez de cruzarse.
-- Lo demás de la función no cambia.
--
-- ANTES DE APLICAR EN PRODUCCIÓN: correr 20261027_venta_concurrente.ENSAYO.sql (termina en
-- ROLLBACK) y las pruebas database/tests/venta_concurrente.sql y venta_concurrente.py.

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_registrar_venta_idempotente(
    p_clave UUID,
    p_sucursal_id INTEGER,
    p_cajero_id INTEGER,
    p_medio_pago CHARACTER VARYING,
    p_items JSONB,
    p_tipo_venta CHARACTER VARYING DEFAULT 'normal',
    p_empleado_id INTEGER DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $function$
DECLARE
    v_existente public.ventas_idempotencia%ROWTYPE;
    v_venta_id  INTEGER;
BEGIN
    IF p_clave IS NULL THEN
        RAISE EXCEPTION 'Falta la clave única de la venta' USING ERRCODE = '22023';
    END IF;

    -- Dos envíos simultáneos de la misma venta: el segundo espera al primero.
    PERFORM pg_advisory_xact_lock(hashtextextended(p_clave::text, 0));

    SELECT * INTO v_existente FROM public.ventas_idempotencia WHERE clave = p_clave;
    IF FOUND THEN
        IF v_existente.cajero_id IS DISTINCT FROM p_cajero_id THEN
            RAISE EXCEPTION 'La clave de esta venta pertenece a otro cajero' USING ERRCODE = '42501';
        END IF;
        RETURN v_existente.venta_id;  -- reintento: la venta ya quedó registrada
    END IF;

    -- H3.2 T05: bloquear de una vez, y en orden fijo, todo el stock que tocará la venta.
    PERFORM public.fn_bloquear_stock_venta(p_sucursal_id, p_items);

    v_venta_id := public.fn_registrar_venta(
        p_sucursal_id, p_cajero_id, p_medio_pago, p_items, p_tipo_venta, p_empleado_id);

    INSERT INTO public.ventas_idempotencia (clave, venta_id, cajero_id)
    VALUES (p_clave, v_venta_id, p_cajero_id);

    RETURN v_venta_id;
END;
$function$;

-- Crea las filas de stock que falten (en 0, como haría la venta) y las bloquea en orden.
CREATE OR REPLACE FUNCTION public.fn_bloquear_stock_venta(p_sucursal_id INTEGER, p_items JSONB)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $function$
DECLARE
    v_productos    INTEGER[];
    v_ingredientes INTEGER[];
    v_reventa      INTEGER[];
BEGIN
    SELECT coalesce(array_agg(DISTINCT p.id), '{}')
      INTO v_productos
      FROM jsonb_array_elements(p_items) item
      JOIN public.productos p ON p.nombre = item->>'producto' AND p.activo;

    SELECT coalesce(array_agg(DISTINCT r.ingrediente_id), '{}')
      INTO v_ingredientes
      FROM public.recetas r
     WHERE r.producto_id = ANY (v_productos);

    SELECT coalesce(array_agg(u.producto_id), '{}')
      INTO v_reventa
      FROM unnest(v_productos) AS u(producto_id)
     WHERE NOT EXISTS (SELECT 1 FROM public.recetas r WHERE r.producto_id = u.producto_id);

    -- 1) Ingredientes de los productos con receta, por id.
    INSERT INTO public.stock_sucursal (ingrediente_id, sucursal_id, stock_actual, stock_minimo)
    SELECT i, p_sucursal_id, 0, 0 FROM unnest(v_ingredientes) i ORDER BY i
    ON CONFLICT (ingrediente_id, sucursal_id) DO NOTHING;

    PERFORM 1 FROM public.stock_sucursal
     WHERE sucursal_id = p_sucursal_id AND ingrediente_id = ANY (v_ingredientes)
     ORDER BY ingrediente_id
       FOR UPDATE;

    -- 2) Productos sin receta (stock propio, H3.2), por id.
    INSERT INTO public.stock_producto_sucursal (producto_id, sucursal_id, stock_actual, stock_minimo)
    SELECT p, p_sucursal_id, 0, 0 FROM unnest(v_reventa) p ORDER BY p
    ON CONFLICT (producto_id, sucursal_id) DO NOTHING;

    PERFORM 1 FROM public.stock_producto_sucursal
     WHERE sucursal_id = p_sucursal_id AND producto_id = ANY (v_reventa)
     ORDER BY producto_id
       FOR UPDATE;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_bloquear_stock_venta(integer, jsonb) FROM PUBLIC;

COMMIT;


-- #####################################################################
-- 45. database/migrations/20261027_version_inventario.sql
-- #####################################################################

-- H3.2 T06 - Los cambios confirmados llegan al panel de Inventario (H3.4) y a sus alertas
-- de stock mínimo (H3.5) sin recargar, en 2 segundos o menos.
--
-- No hay canal de tiempo real (H3.4 T06 se descartó: sin WebSockets). En su lugar el panel
-- pregunta cada 2 s, mientras está visible, una "versión" muy liviana del inventario y solo
-- vuelve a cargar las existencias cuando cambió.
--
-- fn_version_inventario() devuelve:
--   - stock: huella (md5) del stock actual y del mínimo de cada fila de stock_sucursal y
--     stock_producto_sucursal. Cambia con ventas, anulaciones, compras, ajustes, mermas y
--     también al editar un mínimo (que no deja movimiento en el kardex).
--   - movimientos: id del último movimiento del kardex (para refrescar el reporte de mermas).
-- Solo lectura (STABLE). SECURITY DEFINER para que el bodeguero no necesite leer el kardex
-- completo. Ejecutable por admin y bodeguero, como el panel.
--
-- ANTES DE APLICAR EN PRODUCCIÓN: correr 20261027_version_inventario.ENSAYO.sql (termina en
-- ROLLBACK) y la prueba database/tests/version_inventario.sql.

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_version_inventario()
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $function$
    SELECT jsonb_build_object(
        'stock', md5(coalesce((
            SELECT string_agg(concat_ws(':', t, item_id, sucursal_id, stock_actual, stock_minimo), ','
                              ORDER BY t, item_id, sucursal_id)
              FROM (SELECT 'i' AS t, ingrediente_id AS item_id, sucursal_id, stock_actual, stock_minimo
                      FROM public.stock_sucursal
                    UNION ALL
                    SELECT 'p', producto_id, sucursal_id, stock_actual, stock_minimo
                      FROM public.stock_producto_sucursal) s), '')),
        'movimientos', coalesce((SELECT max(id) FROM public.movimientos_stock), 0)
    );
$function$;

COMMENT ON FUNCTION public.fn_version_inventario() IS
    'Versión liviana del inventario (H3.2 T06): el panel la consulta cada 2 s y recarga solo si cambió.';

REVOKE ALL ON FUNCTION public.fn_version_inventario() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_version_inventario() TO nury_admin, nury_bodeguero;

COMMIT;

NOTIFY pgrst, 'reload schema';


-- #####################################################################
-- 46. database/migrations/20261030_articulos_por_comprar.sql
-- #####################################################################

-- Inventario > "Por comprar": artículos críticos para la compra del día siguiente.
--
-- Las compras se hacen a diario. Un artículo entra en la lista cuando su stock no alcanza
-- para cubrir el mínimo más lo que se consume en un día:
--
--     consumo_diario = lo vendido en los últimos p_dias días (ventas menos anulaciones) / p_dias
--     stock_objetivo = stock_minimo + consumo_diario
--     entra si stock_actual < stock_objetivo
--     sugerido       = stock_objetivo - stock_actual
--                      (productos en unidades enteras hacia arriba; materias primas a 3 decimales)
--
-- Devuelve también "vendido": el total vendido en el periodo (ventas menos anulaciones). La
-- pantalla muestra ese total y no el promedio diario, que en productos daría fracciones de
-- unidad sin sentido (1 bebida en 7 días = 0,143 por día).
--
-- Considera materias primas (stock_sucursal) y productos sin receta (stock_producto_sucursal),
-- activos, con la misma definición de artículo que v_existencias_articulos (H3.3). Un artículo
-- sin mínimo y sin ventas en el periodo no entra: no hay con qué calcular cuánto comprar.
--
-- p_sucursal_id NULL = todas las sucursales. Como el resto del panel de Inventario, el
-- bodeguero queda limitado a su sucursal en el front; la base no restringe la lectura por
-- sucursal (H3.4 T08).
-- Solo lectura (STABLE). SECURITY DEFINER, ejecutable por admin y bodeguero.
--
-- ANTES DE APLICAR EN PRODUCCIÓN: correr 20261030_articulos_por_comprar.ENSAYO.sql (termina
-- en ROLLBACK) y la prueba database/tests/articulos_por_comprar.sql.

BEGIN;

-- Cambió la lista de columnas (se agregó "vendido"): CREATE OR REPLACE no puede cambiarla.
DROP FUNCTION IF EXISTS public.fn_articulos_por_comprar(integer, integer);

CREATE OR REPLACE FUNCTION public.fn_articulos_por_comprar(
    p_sucursal_id INTEGER DEFAULT NULL,
    p_dias        INTEGER DEFAULT 7
)
RETURNS TABLE (
    tipo           VARCHAR,
    articulo_id    INTEGER,
    nombre         VARCHAR,
    unidad         VARCHAR,
    sucursal_id    INTEGER,
    sucursal       VARCHAR,
    stock_actual   NUMERIC,
    stock_minimo   NUMERIC,
    vendido        NUMERIC,
    consumo_diario NUMERIC,
    stock_objetivo NUMERIC,
    sugerido       NUMERIC
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $function$
BEGIN
    IF p_dias IS NULL OR p_dias < 1 OR p_dias > 90 THEN
        RAISE EXCEPTION 'El periodo de consumo debe ser de 1 a 90 días'
            USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    WITH consumo AS (
        -- Ventas descuentan (cantidad negativa) y las anulaciones devuelven (positiva).
        SELECT CASE WHEN m.ingrediente_id IS NOT NULL THEN 'materia_prima' ELSE 'producto' END AS c_tipo,
               COALESCE(m.ingrediente_id, m.producto_id) AS c_articulo_id,
               m.sucursal_id                             AS c_sucursal_id,
               -sum(m.cantidad)                          AS vendido
          FROM public.movimientos_stock m
         WHERE m.tipo_movimiento IN ('venta', 'anulacion_venta')
           AND m.creado_en >= now() - make_interval(days => p_dias)
           AND (p_sucursal_id IS NULL OR m.sucursal_id = p_sucursal_id)
         GROUP BY 1, 2, 3
    ), base AS (
        SELECT e.tipo AS b_tipo, e.articulo_id AS b_articulo_id, e.nombre AS b_nombre,
               e.unidad AS b_unidad, e.sucursal_id AS b_sucursal_id, e.sucursal AS b_sucursal,
               e.stock_actual AS b_stock, e.stock_minimo AS b_minimo,
               greatest(COALESCE(c.vendido, 0), 0) AS b_vendido,
               round(greatest(COALESCE(c.vendido, 0), 0) / p_dias, 3) AS b_consumo
          FROM public.v_existencias_articulos e
          LEFT JOIN consumo c
                 ON c.c_tipo = e.tipo
                AND c.c_articulo_id = e.articulo_id
                AND c.c_sucursal_id = e.sucursal_id
         WHERE e.activo
           AND (p_sucursal_id IS NULL OR e.sucursal_id = p_sucursal_id)
    )
    SELECT b.b_tipo::VARCHAR, b.b_articulo_id, b.b_nombre::VARCHAR, b.b_unidad::VARCHAR,
           b.b_sucursal_id, b.b_sucursal::VARCHAR,
           b.b_stock, b.b_minimo, b.b_vendido, b.b_consumo,
           b.b_minimo + b.b_consumo,
           CASE WHEN b.b_tipo = 'producto'
                THEN ceil(b.b_minimo + b.b_consumo - b.b_stock)
                ELSE ceil((b.b_minimo + b.b_consumo - b.b_stock) * 1000) / 1000
           END
      FROM base b
     WHERE b.b_stock < b.b_minimo + b.b_consumo
     ORDER BY b.b_sucursal, (b.b_stock <= 0) DESC, b.b_nombre;
END;
$function$;

COMMENT ON FUNCTION public.fn_articulos_por_comprar(integer, integer) IS
    'Artículos activos cuyo stock no cubre mínimo + consumo diario (promedio de ventas de los últimos p_dias días), con lo vendido en el periodo y la cantidad sugerida a comprar.';

REVOKE ALL ON FUNCTION public.fn_articulos_por_comprar(integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_articulos_por_comprar(integer, integer) TO nury_admin, nury_bodeguero;

COMMIT;

NOTIFY pgrst, 'reload schema';


-- #####################################################################
-- 47. database/migrations/20261101_direcciones_factura_xml.sql
-- #####################################################################

-- Facturas XML: guarda las direcciones del emisor, del receptor y de despacho.
--
-- El front las usa para elegir la sucursal que recibe el stock (la dirección de despacho y,
-- si no coincide, la de facturación, comparadas con sucursales.direccion). Aquí quedan
-- guardadas con la factura.
--
-- Se leen del XML que ya se guarda (facturas_xml_pendientes.xml_original) con un disparador,
-- así fn_ingresar_factura_xml no cambia. Las facturas ya ingresadas se completan al aplicar.
-- Las direcciones son informativas: si no se pueden leer quedan NULL y nunca impiden ingresar.
-- Mismo formato que el lector del navegador (lector-dte.ts): «calle, comuna»; sin calle, NULL.
--
-- ANTES DE APLICAR EN PRODUCCIÓN: correr 20261101_direcciones_factura_xml.ENSAYO.sql (termina
-- en ROLLBACK).

BEGIN;

ALTER TABLE public.facturas_xml_pendientes
    ADD COLUMN IF NOT EXISTS direccion_emisor   VARCHAR(250),
    ADD COLUMN IF NOT EXISTS direccion_receptor VARCHAR(250),
    ADD COLUMN IF NOT EXISTS direccion_despacho VARCHAR(250);

-- 1) XML guardado → documento, con la misma decodificación que fn_ingresar_factura_xml ------
-- NULL si no se puede leer.

CREATE OR REPLACE FUNCTION public.fn_dte_xml(p_bytes BYTEA)
RETURNS XML
LANGUAGE plpgsql
IMMUTABLE
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_contenido    BYTEA := p_bytes;
    v_codificacion TEXT;
BEGIN
    IF substring(p_bytes FROM 1 FOR 3) = '\xefbbbf'::BYTEA THEN
        v_contenido := substring(p_bytes FROM 4);
        v_codificacion := 'UTF8';
    ELSE
        v_codificacion := COALESCE(
            substring(convert_from(substring(p_bytes FROM 1 FOR 200), 'LATIN1')
                      FROM '^\s*<\?xml[^>]*encoding\s*=\s*["'']([^"'']+)["'']'),
            'UTF8');
    END IF;
    RETURN XMLPARSE(DOCUMENT regexp_replace(convert_from(v_contenido, v_codificacion), '^\s*<\?xml[^>]*\?>', ''));
EXCEPTION WHEN OTHERS THEN
    -- Un archivo que no se puede leer deja las direcciones vacías y no detiene el relleno.
    RETURN NULL;
END;
$$;

-- 2) «AVENIDA ESPAÑA 1680, VALPARAISO» -----------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_dte_direccion(p_doc XML, p_padre TEXT, p_calle TEXT, p_comuna TEXT)
RETURNS VARCHAR
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT left(concat_ws(', ', calle, public.fn_dte_texto(p_doc, p_padre || '/' || p_comuna)), 250)
      FROM (SELECT public.fn_dte_texto(p_doc, p_padre || '/' || p_calle) AS calle) AS d
     WHERE calle IS NOT NULL;
$$;

-- 3) Disparador: completa las direcciones al guardar la factura ------------------------------

CREATE OR REPLACE FUNCTION public.fn_direcciones_factura_xml()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_doc XML;
BEGIN
    BEGIN
        v_doc := public.fn_dte_xml(NEW.xml_original);
        NEW.direccion_emisor   := public.fn_dte_direccion(v_doc, 'Encabezado/Emisor', 'DirOrigen', 'CmnaOrigen');
        NEW.direccion_receptor := public.fn_dte_direccion(v_doc, 'Encabezado/Receptor', 'DirRecep', 'CmnaRecep');
        NEW.direccion_despacho := public.fn_dte_direccion(v_doc, 'Encabezado/Transporte', 'DirDest', 'CmnaDest');
    EXCEPTION WHEN OTHERS THEN
        -- fn_ingresar_factura_xml ya validó el XML; un caso raro solo deja las direcciones vacías.
        NULL;
    END;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_direcciones_factura_xml ON public.facturas_xml_pendientes;
CREATE TRIGGER trg_direcciones_factura_xml
BEFORE INSERT ON public.facturas_xml_pendientes
FOR EACH ROW EXECUTE FUNCTION public.fn_direcciones_factura_xml();

REVOKE ALL ON FUNCTION public.fn_dte_xml(bytea) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_dte_direccion(xml, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_direcciones_factura_xml() FROM PUBLIC;

-- 4) Facturas ya ingresadas ------------------------------------------------------------------
-- trg_facturas_xml_permisos exige una sesión de la app en cada UPDATE (pgAdmin no la tiene);
-- se desactiva solo durante este relleno, que no cambia sucursal ni quién la cargó.

ALTER TABLE public.facturas_xml_pendientes DISABLE TRIGGER trg_facturas_xml_permisos;

UPDATE public.facturas_xml_pendientes AS f
   SET direccion_emisor   = d.emisor,
       direccion_receptor = d.receptor,
       direccion_despacho = d.despacho
  FROM (
        SELECT id,
               public.fn_dte_direccion(doc, 'Encabezado/Emisor', 'DirOrigen', 'CmnaOrigen')    AS emisor,
               public.fn_dte_direccion(doc, 'Encabezado/Receptor', 'DirRecep', 'CmnaRecep')    AS receptor,
               public.fn_dte_direccion(doc, 'Encabezado/Transporte', 'DirDest', 'CmnaDest')    AS despacho
          FROM (SELECT id, public.fn_dte_xml(xml_original) AS doc
                  FROM public.facturas_xml_pendientes
                 WHERE direccion_emisor IS NULL AND direccion_receptor IS NULL AND direccion_despacho IS NULL) AS x
       ) AS d
 WHERE f.id = d.id;

ALTER TABLE public.facturas_xml_pendientes ENABLE TRIGGER trg_facturas_xml_permisos;

COMMIT;


-- #####################################################################
-- 48. database/migrations/20261104_reporte_cajeros.sql
-- #####################################################################

-- H4.3 T02 - Métricas por cajero (Reporte de desempeño por cajero).
--
-- fn_reporte_cajeros(p_sucursales, p_desde, p_hasta) devuelve una fila por cajero con, al
-- menos, lo que pide H4.3: total vendido, número de ventas, venta promedio y cantidad de
-- productos vendidos. Las ventas anuladas no cuentan en esas métricas y van aparte
-- (anuladas, total_anuladas) para revisar la frecuencia de anulaciones.
--
-- Mismo período (días en hora de Chile, ambos incluidos) y filtro de sucursales que
-- fn_reporte_ventas_sucursal (H4.1 T02); p_sucursales NULL = todas. Las ventas sin cajero
-- atribuido (cajero_id NULL, permitido por el esquema) salen como "Sin cajero".
-- La venta a empleado se atribuye al cajero que la registró, con su total ya descontado.
-- El filtro por turno real (H4.3 T03) y la comparación con el período anterior (H4.3 T05)
-- se agregan después; la pantalla compara llamando a esta función con el período anterior.
--
-- Solo lectura (STABLE). SECURITY DEFINER, ejecutable solo por el administrador.
--
-- ANTES DE APLICAR EN PRODUCCIÓN: correr 20261104_reporte_cajeros.ENSAYO.sql (termina en
-- ROLLBACK) y la prueba database/tests/reporte_cajeros.sql.

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_reporte_cajeros(
    p_sucursales INTEGER[],
    p_desde      DATE,
    p_hasta      DATE
)
RETURNS TABLE (
    cajero_id      INTEGER,
    cajero         VARCHAR,
    sucursales     VARCHAR,
    turnos         INTEGER,
    ventas         INTEGER,
    total          NUMERIC,
    venta_promedio NUMERIC,
    productos      NUMERIC,
    anuladas       INTEGER,
    total_anuladas NUMERIC
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $function$
DECLARE
    v_desde TIMESTAMP;
    v_hasta TIMESTAMP;
BEGIN
    IF p_desde IS NULL OR p_hasta IS NULL THEN
        RAISE EXCEPTION 'Indica la fecha inicial y la final del período' USING ERRCODE = '22023';
    END IF;
    IF p_desde > p_hasta THEN
        RAISE EXCEPTION 'La fecha inicial no puede ser posterior a la final' USING ERRCODE = '22023';
    END IF;
    IF p_hasta - p_desde > 366 THEN
        RAISE EXCEPTION 'El período no puede superar un año' USING ERRCODE = '22023';
    END IF;

    v_desde := (p_desde::timestamp AT TIME ZONE 'America/Santiago') AT TIME ZONE current_setting('TimeZone');
    v_hasta := ((p_hasta + 1)::timestamp AT TIME ZONE 'America/Santiago') AT TIME ZONE current_setting('TimeZone');

    RETURN QUERY
    WITH del_periodo AS (
        SELECT v.id AS v_id, v.cajero_id AS v_cajero, v.sucursal_id AS v_sucursal,
               v.turno_id AS v_turno, v.total AS v_total, v.anulada AS v_anulada
          FROM public.ventas v
         WHERE v.fecha_venta >= v_desde
           AND v.fecha_venta <  v_hasta
           AND (p_sucursales IS NULL OR v.sucursal_id = ANY (p_sucursales) OR v.sucursal_id IS NULL)
    ), unidades AS (
        SELECT d.venta_id AS u_venta, sum(d.cantidad) AS u_cantidad
          FROM public.detalle_venta d
         WHERE d.venta_id IN (SELECT dp.v_id FROM del_periodo dp WHERE NOT dp.v_anulada)
         GROUP BY d.venta_id
    )
    SELECT dp.v_cajero,
           COALESCE(u.nombre, 'Sin cajero')::varchar,
           COALESCE(string_agg(DISTINCT s.nombre, ', '), 'Sin sucursal')::varchar,
           count(DISTINCT dp.v_turno)::int,
           count(*) FILTER (WHERE NOT dp.v_anulada)::int,
           COALESCE(sum(dp.v_total) FILTER (WHERE NOT dp.v_anulada), 0),
           CASE WHEN count(*) FILTER (WHERE NOT dp.v_anulada) = 0 THEN 0
                ELSE round(sum(dp.v_total) FILTER (WHERE NOT dp.v_anulada)
                           / count(*) FILTER (WHERE NOT dp.v_anulada), 2) END,
           COALESCE(sum(un.u_cantidad), 0),
           count(*) FILTER (WHERE dp.v_anulada)::int,
           COALESCE(sum(dp.v_total) FILTER (WHERE dp.v_anulada), 0)
      FROM del_periodo dp
      LEFT JOIN public.usuarios u   ON u.id = dp.v_cajero
      LEFT JOIN public.sucursales s ON s.id = dp.v_sucursal
      LEFT JOIN unidades un         ON un.u_venta = dp.v_id
     GROUP BY dp.v_cajero, u.nombre
     ORDER BY dp.v_cajero IS NULL, COALESCE(sum(dp.v_total) FILTER (WHERE NOT dp.v_anulada), 0) DESC, u.nombre;
END;
$function$;

COMMENT ON FUNCTION public.fn_reporte_cajeros(integer[], date, date) IS
    'H4.3: por cajero, total vendido, ventas, venta promedio y productos vendidos sin anuladas (que van aparte), en un período de días en hora de Chile.';

REVOKE ALL ON FUNCTION public.fn_reporte_cajeros(integer[], date, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_reporte_cajeros(integer[], date, date) TO nury_admin;

COMMIT;

NOTIFY pgrst, 'reload schema';


-- #####################################################################
-- 49. database/migrations/20261104_reporte_productos_sucursal.sql
-- #####################################################################

-- H4.1 T03 - Productos vendidos por sucursal (Reportes de ventas por sucursal).
--
-- fn_reporte_productos_sucursal(p_sucursales, p_desde, p_hasta) devuelve una fila por
-- sucursal y producto con las unidades vendidas y el monto, sin las ventas anuladas. Usa el
-- mismo período (días en hora de Chile, ambos incluidos) y el mismo filtro de sucursales que
-- fn_reporte_ventas_sucursal (H4.1 T02); p_sucursales NULL = todas.
--
-- Monto: monto_bruto es la suma de los subtotales de detalle_venta (precio cobrado ×
-- cantidad). En una venta a empleado el 30 % se descuenta sobre el total de la venta, no en
-- cada línea (0005_venta_empleado_descuento.sql); aquí ese descuento se reparte entre las
-- líneas según su subtotal, para que monto (= bruto − descuento) de todos los productos de
-- una sucursal sume lo mismo que su total en el resumen de T02 (salvo centavos de redondeo).
--
-- "Sin sucursal": como en T02, una venta sin sucursal (hoy imposible: NOT NULL) saldría con
-- sucursal_id NULL y sucursal "Sin sucursal" en vez de quedar fuera.
--
-- con_receta indica si el producto tiene receta hoy: sirve para la cuadratura con
-- movimientos_stock (H4.1 T04), donde un producto con receta descuenta sus ingredientes.
-- Sirve también para H4.4 (unidades y monto por producto).
--
-- Solo lectura (STABLE). SECURITY DEFINER, ejecutable solo por el administrador.
--
-- ANTES DE APLICAR EN PRODUCCIÓN: correr 20261104_reporte_productos_sucursal.ENSAYO.sql
-- (termina en ROLLBACK) y la prueba database/tests/reporte_productos_sucursal.sql.

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_reporte_productos_sucursal(
    p_sucursales INTEGER[],
    p_desde      DATE,
    p_hasta      DATE
)
RETURNS TABLE (
    sucursal_id INTEGER,
    sucursal    VARCHAR,
    producto_id INTEGER,
    producto    VARCHAR,
    categoria   VARCHAR,
    con_receta  BOOLEAN,
    unidades    NUMERIC,
    ventas      INTEGER,
    monto_bruto NUMERIC,
    descuento   NUMERIC,
    monto       NUMERIC
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $function$
DECLARE
    v_desde TIMESTAMP;
    v_hasta TIMESTAMP;
BEGIN
    IF p_desde IS NULL OR p_hasta IS NULL THEN
        RAISE EXCEPTION 'Indica la fecha inicial y la final del período' USING ERRCODE = '22023';
    END IF;
    IF p_desde > p_hasta THEN
        RAISE EXCEPTION 'La fecha inicial no puede ser posterior a la final' USING ERRCODE = '22023';
    END IF;
    IF p_hasta - p_desde > 366 THEN
        RAISE EXCEPTION 'El período no puede superar un año' USING ERRCODE = '22023';
    END IF;

    -- Mismos límites que fn_reporte_ventas_sucursal: días de Chile en la zona de fecha_venta.
    v_desde := (p_desde::timestamp AT TIME ZONE 'America/Santiago') AT TIME ZONE current_setting('TimeZone');
    v_hasta := ((p_hasta + 1)::timestamp AT TIME ZONE 'America/Santiago') AT TIME ZONE current_setting('TimeZone');

    RETURN QUERY
    WITH lineas AS (
        SELECT v.id AS l_venta, v.sucursal_id AS l_sucursal, v.descuento_monto AS l_desc_venta,
               d.producto_id AS l_producto, d.cantidad AS l_cantidad, d.subtotal AS l_subtotal,
               sum(d.subtotal) OVER (PARTITION BY v.id) AS l_subtotal_venta
          FROM public.ventas v
          JOIN public.detalle_venta d ON d.venta_id = v.id
         WHERE NOT v.anulada
           AND v.fecha_venta >= v_desde
           AND v.fecha_venta <  v_hasta
           AND (p_sucursales IS NULL OR v.sucursal_id = ANY (p_sucursales) OR v.sucursal_id IS NULL)
    ), con_descuento AS (
        SELECT l.*,
               CASE WHEN l.l_desc_venta > 0 AND l.l_subtotal_venta > 0
                    THEN l.l_desc_venta * l.l_subtotal / l.l_subtotal_venta
                    ELSE 0 END AS l_descuento
          FROM lineas l
    )
    SELECT c.l_sucursal,
           COALESCE(s.nombre, 'Sin sucursal')::varchar,
           c.l_producto,
           p.nombre::varchar,
           p.categoria::varchar,
           EXISTS (SELECT 1 FROM public.recetas r WHERE r.producto_id = c.l_producto),
           sum(c.l_cantidad),
           count(DISTINCT c.l_venta)::int,
           sum(c.l_subtotal),
           round(sum(c.l_descuento), 2),
           round(sum(c.l_subtotal - c.l_descuento), 2)
      FROM con_descuento c
      JOIN public.productos p ON p.id = c.l_producto
      LEFT JOIN public.sucursales s ON s.id = c.l_sucursal
     GROUP BY c.l_sucursal, s.nombre, c.l_producto, p.nombre, p.categoria
     ORDER BY c.l_sucursal IS NULL, s.nombre, sum(c.l_subtotal - c.l_descuento) DESC, p.nombre;
END;
$function$;

COMMENT ON FUNCTION public.fn_reporte_productos_sucursal(integer[], date, date) IS
    'H4.1: unidades y monto por sucursal y producto en un período de días en hora de Chile, sin ventas anuladas; el descuento de las ventas a empleado se reparte entre sus líneas.';

REVOKE ALL ON FUNCTION public.fn_reporte_productos_sucursal(integer[], date, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_reporte_productos_sucursal(integer[], date, date) TO nury_admin;

COMMIT;

NOTIFY pgrst, 'reload schema';


-- #####################################################################
-- 50. database/migrations/20261104_reporte_ventas_sucursal.sql
-- #####################################################################

-- H4.1 T02 - Resumen de ventas por sucursal y período (Reportes de ventas por sucursal).
--
-- fn_reporte_ventas_sucursal(p_sucursales, p_desde, p_hasta) devuelve UNA FILA POR SUCURSAL,
-- nunca solo la suma de todas: el reporte sirve para comparar una sucursal contra otra.
--   - p_sucursales: ids a incluir; NULL = todas. Las sucursales pedidas aparecen aunque no
--     tengan ventas en el período (en 0), para que la comparación no las esconda.
--   - p_desde / p_hasta: días en hora de Chile, ambos incluidos. El front traduce "día",
--     "semana", "mes" o "rango personalizado" a estas dos fechas.
-- Por sucursal: ventas válidas, total, ticket promedio, totales por medio de pago, ventas
-- normales y de empleado por separado, y las anuladas aparte (no suman al total).
--
-- "Sin sucursal": ventas.sucursal_id es NOT NULL (verificado en producción el 04-11-2026: 0
-- ventas sin sucursal), así que hoy no puede ocurrir. Igual, si llegara a existir una venta
-- sin sucursal, sale en su propia fila "Sin sucursal" en vez de quedar fuera del reporte.
--
-- Hora: fecha_venta es TIMESTAMP sin zona, escrito con now() en la zona del servidor
-- (current_setting('TimeZone'), UTC en el VPS). Los límites del período se calculan en hora
-- de Chile y se pasan a esa zona, así la consulta usa el índice (sucursal_id, fecha_venta).
--
-- Solo lectura (STABLE). SECURITY DEFINER, ejecutable solo por el administrador.
--
-- ANTES DE APLICAR EN PRODUCCIÓN: correr 20261104_reporte_ventas_sucursal.ENSAYO.sql (termina
-- en ROLLBACK) y la prueba database/tests/reporte_ventas_sucursal.sql.

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_reporte_ventas_sucursal(
    p_sucursales INTEGER[],
    p_desde      DATE,
    p_hasta      DATE
)
RETURNS TABLE (
    sucursal_id     INTEGER,
    sucursal        VARCHAR,
    ventas          INTEGER,
    total           NUMERIC,
    ticket_promedio NUMERIC,
    ventas_normales INTEGER,
    total_normales  NUMERIC,
    ventas_empleado INTEGER,
    total_empleado  NUMERIC,
    medios_pago     JSONB,
    anuladas        INTEGER,
    total_anuladas  NUMERIC
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $function$
DECLARE
    v_desde TIMESTAMP;
    v_hasta TIMESTAMP;
BEGIN
    IF p_desde IS NULL OR p_hasta IS NULL THEN
        RAISE EXCEPTION 'Indica la fecha inicial y la final del período' USING ERRCODE = '22023';
    END IF;
    IF p_desde > p_hasta THEN
        RAISE EXCEPTION 'La fecha inicial no puede ser posterior a la final' USING ERRCODE = '22023';
    END IF;
    IF p_hasta - p_desde > 366 THEN
        RAISE EXCEPTION 'El período no puede superar un año' USING ERRCODE = '22023';
    END IF;

    -- Inicio del primer día y del día siguiente al último, en hora de Chile, llevados a la
    -- zona en que se guardó fecha_venta.
    v_desde := (p_desde::timestamp AT TIME ZONE 'America/Santiago') AT TIME ZONE current_setting('TimeZone');
    v_hasta := ((p_hasta + 1)::timestamp AT TIME ZONE 'America/Santiago') AT TIME ZONE current_setting('TimeZone');

    RETURN QUERY
    WITH del_periodo AS (
        SELECT v.sucursal_id AS v_sucursal_id, v.total AS v_total, v.anulada AS v_anulada,
               v.tipo_venta AS v_tipo, COALESCE(NULLIF(btrim(v.medio_pago), ''), 'sin_medio') AS v_medio
          FROM public.ventas v
         WHERE v.fecha_venta >= v_desde
           AND v.fecha_venta <  v_hasta
           AND (p_sucursales IS NULL OR v.sucursal_id = ANY (p_sucursales) OR v.sucursal_id IS NULL)
    ), por_sucursal AS (
        SELECT d.v_sucursal_id AS s_id,
               count(*) FILTER (WHERE NOT d.v_anulada)::int                              AS s_ventas,
               COALESCE(sum(d.v_total) FILTER (WHERE NOT d.v_anulada), 0)                AS s_total,
               count(*) FILTER (WHERE NOT d.v_anulada AND d.v_tipo = 'normal')::int      AS s_normales,
               COALESCE(sum(d.v_total) FILTER (WHERE NOT d.v_anulada AND d.v_tipo = 'normal'), 0) AS s_total_normales,
               count(*) FILTER (WHERE NOT d.v_anulada AND d.v_tipo = 'empleado')::int    AS s_empleado,
               COALESCE(sum(d.v_total) FILTER (WHERE NOT d.v_anulada AND d.v_tipo = 'empleado'), 0) AS s_total_empleado,
               count(*) FILTER (WHERE d.v_anulada)::int                                  AS s_anuladas,
               COALESCE(sum(d.v_total) FILTER (WHERE d.v_anulada), 0)                    AS s_total_anuladas
          FROM del_periodo d
         GROUP BY d.v_sucursal_id
    ), por_medio AS (
        SELECT m.s_id, jsonb_object_agg(m.medio, m.monto ORDER BY m.medio) AS s_medios
          FROM (SELECT d.v_sucursal_id AS s_id, d.v_medio AS medio, sum(d.v_total) AS monto
                  FROM del_periodo d
                 WHERE NOT d.v_anulada
                 GROUP BY 1, 2) m
         GROUP BY m.s_id
    ), sucursales_pedidas AS (
        -- Las pedidas (o todas las activas) aparecen aunque no tengan ventas; una inactiva
        -- aparece si vendió en el período.
        SELECT s.id AS s_id, s.nombre::varchar AS s_nombre
          FROM public.sucursales s
         WHERE (p_sucursales IS NULL AND s.activo) OR s.id = ANY (p_sucursales)
        UNION
        SELECT s.id, s.nombre::varchar
          FROM public.sucursales s
          JOIN por_sucursal ps ON ps.s_id = s.id
    ), filas AS (
        SELECT sp.s_id, sp.s_nombre FROM sucursales_pedidas sp
        UNION ALL
        SELECT NULL::int, 'Sin sucursal'::varchar
         WHERE EXISTS (SELECT 1 FROM por_sucursal ps WHERE ps.s_id IS NULL)
    )
    SELECT f.s_id,
           f.s_nombre,
           COALESCE(ps.s_ventas, 0),
           COALESCE(ps.s_total, 0),
           CASE WHEN COALESCE(ps.s_ventas, 0) = 0 THEN 0 ELSE round(ps.s_total / ps.s_ventas, 2) END,
           COALESCE(ps.s_normales, 0),
           COALESCE(ps.s_total_normales, 0),
           COALESCE(ps.s_empleado, 0),
           COALESCE(ps.s_total_empleado, 0),
           COALESCE(pm.s_medios, '{}'::jsonb),
           COALESCE(ps.s_anuladas, 0),
           COALESCE(ps.s_total_anuladas, 0)
      FROM filas f
      LEFT JOIN por_sucursal ps ON ps.s_id IS NOT DISTINCT FROM f.s_id
      LEFT JOIN por_medio pm   ON pm.s_id IS NOT DISTINCT FROM f.s_id
     ORDER BY f.s_id IS NULL, f.s_nombre;
END;
$function$;

COMMENT ON FUNCTION public.fn_reporte_ventas_sucursal(integer[], date, date) IS
    'H4.1: una fila por sucursal (y "Sin sucursal" si hay ventas sin ella) con ventas, total, ticket promedio, medios de pago, normales/empleado y anuladas aparte, en un período de días en hora de Chile.';

REVOKE ALL ON FUNCTION public.fn_reporte_ventas_sucursal(integer[], date, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_reporte_ventas_sucursal(integer[], date, date) TO nury_admin;

COMMIT;

NOTIFY pgrst, 'reload schema';


-- #####################################################################
-- 51. database/migrations/20261105_consumo_diario_articulos.sql
-- #####################################################################

-- H4.5 T02 - Vista de consumo promedio diario por sucursal para sugerencias de compra.
--
-- Calcula el consumo diario promedio por artículo y sucursal de las últimas 4 semanas (28 días)
-- a partir de las ventas netas (ventas menos anulaciones) y salidas por mermas registradas
-- en movimientos_stock.
--
-- Campos principales:
-- - dias_con_historial: días transcurridos desde el primer movimiento registrado del artículo
--   en la sucursal (si es < 28 días, el sistema clasifica como «Datos insuficientes para sugerir»).
-- - total_vendido_28d: suma neta de ventas del periodo.
-- - total_merma_28d: mermas registradas en el periodo.
-- - consumo_total_28d: total de salidas operativas en las 4 semanas.
-- - consumo_diario_promedio: promedio diario (consumo_total_28d / 28.0) redondeado a 3 decimales.
--
-- Se descarta explícitamente cualquier columna de tiempo de reposición o días de entrega
-- en ingredientes, ya que el local opera con reposición diaria Just-in-Time.
--
-- Permisos: SELECT para nury_admin y nury_bodeguero (expuesta vía PostgREST).
--
-- ANTES DE APLICAR EN PRODUCCIÓN: correr 20261105_consumo_diario_articulos.ENSAYO.sql (termina
-- en ROLLBACK) y verificar en la base.

BEGIN;

CREATE OR REPLACE VIEW public.v_consumo_diario_articulos AS
WITH historial AS (
    -- Antigüedad del historial por artículo y sucursal (primer movimiento registrado en el sistema)
    SELECT CASE WHEN m.ingrediente_id IS NOT NULL THEN 'materia_prima' ELSE 'producto' END AS h_tipo,
           COALESCE(m.ingrediente_id, m.producto_id) AS h_articulo_id,
           m.sucursal_id                             AS h_sucursal_id,
           min(m.creado_en)                          AS primer_movimiento
      FROM public.movimientos_stock m
     GROUP BY 1, 2, 3
), consumo_28d AS (
    -- Consumo de las últimas 4 semanas (28 días):
    -- Ventas descuentan (m.cantidad negativa), anulaciones reponen (positiva), mermas descuentan (negativa).
    SELECT CASE WHEN m.ingrediente_id IS NOT NULL THEN 'materia_prima' ELSE 'producto' END AS c_tipo,
           COALESCE(m.ingrediente_id, m.producto_id) AS c_articulo_id,
           m.sucursal_id                             AS c_sucursal_id,
           -sum(CASE WHEN m.tipo_movimiento IN ('venta', 'anulacion_venta') THEN m.cantidad ELSE 0 END) AS vendido,
           -sum(CASE WHEN m.tipo_movimiento = 'merma' THEN m.cantidad ELSE 0 END)                      AS merma
      FROM public.movimientos_stock m
     WHERE m.tipo_movimiento IN ('venta', 'anulacion_venta', 'merma')
       AND m.creado_en >= now() - INTERVAL '28 days'
     GROUP BY 1, 2, 3
)
SELECT e.tipo,
       e.articulo_id,
       e.nombre,
       e.unidad,
       e.activo,
       e.sucursal_id,
       e.sucursal,
       e.stock_actual,
       e.stock_minimo,
       COALESCE(greatest(CURRENT_DATE - h.primer_movimiento::date, 0), 0) AS dias_con_historial,
       greatest(COALESCE(c.vendido, 0), 0)                                 AS total_vendido_28d,
       greatest(COALESCE(c.merma, 0), 0)                                   AS total_merma_28d,
       greatest(COALESCE(c.vendido, 0) + COALESCE(c.merma, 0), 0)         AS consumo_total_28d,
       round(greatest(COALESCE(c.vendido, 0) + COALESCE(c.merma, 0), 0) / 28.0, 3) AS consumo_diario_promedio
  FROM public.v_existencias_articulos e
  LEFT JOIN historial h
         ON h.h_tipo = e.tipo
        AND h.h_articulo_id = e.articulo_id
        AND h.h_sucursal_id = e.sucursal_id
  LEFT JOIN consumo_28d c
         ON c.c_tipo = e.tipo
        AND c.c_articulo_id = e.articulo_id
        AND c.c_sucursal_id = e.sucursal_id
 WHERE e.activo;

COMMENT ON VIEW public.v_consumo_diario_articulos IS
    'Consumo promedio diario de las últimas 4 semanas (28 días) por artículo y sucursal para cálculo de sugerencias de compra (H4.5 T02).';

REVOKE ALL ON public.v_consumo_diario_articulos FROM PUBLIC;
GRANT SELECT ON public.v_consumo_diario_articulos TO nury_admin, nury_bodeguero;

COMMIT;

NOTIFY pgrst, 'reload schema';


-- #####################################################################
-- 52. database/migrations/20261105_cuadratura_ventas_stock.sql
-- #####################################################################

-- H4.1 T04 - Cuadratura del reporte de ventas con movimientos_stock.
--
-- Criterio de H4.1: las cantidades de productos vendidos que muestra el reporte para una
-- sucursal deben coincidir con los movimientos de tipo venta que se generaron en
-- movimientos_stock para esa misma sucursal.
--
-- fn_cuadratura_ventas_stock(p_sucursales, p_desde, p_hasta) compara, por sucursal y artículo,
-- lo que las ventas del período debieron descontar con lo que el kardex registra para esas
-- mismas ventas:
--   - esperado: de las ventas válidas (no anuladas) del período,
--       · producto sin receta en la venta (detalle_venta.receta_version_id NULL): su cantidad;
--       · producto con receta: cada ingrediente de la versión de receta usada en esa venta
--         (recetas_version_detalle) × la cantidad vendida.
--   - registrado: movimientos 'venta' menos 'anulacion_venta' que referencian esas ventas
--     (referencia_tipo = 'venta'), de cualquier venta del período, anulada o no. Una venta
--     anulada y bien repuesta neta 0 y se espera 0; una anulada sin reposición aparece como
--     diferencia.
-- Se compara por venta (referencia_id), no por la fecha del movimiento. Los almuerzos de
-- empleados (consumo_interno) no se mezclan.
-- Devuelve una fila por sucursal y artículo con esperado, registrado, diferencia y si cuadra.
-- Ventas registradas antes de las versiones de receta (20261020) pueden no tener versión y se
-- tratan como sin receta: si en un período antiguo aparecen diferencias, ese es el motivo.
--
-- Solo lectura (STABLE). SECURITY DEFINER, ejecutable solo por el administrador.
--
-- ANTES DE APLICAR EN PRODUCCIÓN: correr 20261105_cuadratura_ventas_stock.ENSAYO.sql (termina
-- en ROLLBACK) y la prueba database/tests/cuadratura_ventas_stock.sql.

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_cuadratura_ventas_stock(
    p_sucursales INTEGER[],
    p_desde      DATE,
    p_hasta      DATE
)
RETURNS TABLE (
    sucursal_id INTEGER,
    sucursal    VARCHAR,
    tipo        VARCHAR,
    articulo_id INTEGER,
    articulo    VARCHAR,
    unidad      VARCHAR,
    esperado    NUMERIC,
    registrado  NUMERIC,
    diferencia  NUMERIC,
    cuadra      BOOLEAN
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $function$
DECLARE
    v_desde TIMESTAMP;
    v_hasta TIMESTAMP;
BEGIN
    IF p_desde IS NULL OR p_hasta IS NULL THEN
        RAISE EXCEPTION 'Indica la fecha inicial y la final del período' USING ERRCODE = '22023';
    END IF;
    IF p_desde > p_hasta THEN
        RAISE EXCEPTION 'La fecha inicial no puede ser posterior a la final' USING ERRCODE = '22023';
    END IF;
    IF p_hasta - p_desde > 366 THEN
        RAISE EXCEPTION 'El período no puede superar un año' USING ERRCODE = '22023';
    END IF;

    v_desde := (p_desde::timestamp AT TIME ZONE 'America/Santiago') AT TIME ZONE current_setting('TimeZone');
    v_hasta := ((p_hasta + 1)::timestamp AT TIME ZONE 'America/Santiago') AT TIME ZONE current_setting('TimeZone');

    RETURN QUERY
    WITH del_periodo AS (
        SELECT v.id AS v_id, v.sucursal_id AS v_sucursal, v.anulada AS v_anulada
          FROM public.ventas v
         WHERE v.fecha_venta >= v_desde
           AND v.fecha_venta <  v_hasta
           AND (p_sucursales IS NULL OR v.sucursal_id = ANY (p_sucursales) OR v.sucursal_id IS NULL)
    ), esperado AS (
        -- Productos sin receta en la venta: su propio stock.
        SELECT dp.v_sucursal AS e_sucursal, 'producto'::varchar AS e_tipo, d.producto_id AS e_id,
               sum(d.cantidad) AS e_cantidad
          FROM del_periodo dp
          JOIN public.detalle_venta d ON d.venta_id = dp.v_id
         WHERE NOT dp.v_anulada AND d.receta_version_id IS NULL
         GROUP BY 1, 2, 3
        UNION ALL
        -- Productos con receta: los ingredientes de la versión usada en esa venta.
        SELECT dp.v_sucursal, 'materia_prima'::varchar, rvd.ingrediente_id,
               sum(rvd.cantidad_necesaria * d.cantidad)
          FROM del_periodo dp
          JOIN public.detalle_venta d ON d.venta_id = dp.v_id
          JOIN public.recetas_version_detalle rvd ON rvd.version_id = d.receta_version_id
         WHERE NOT dp.v_anulada
         GROUP BY 1, 2, 3
    ), esperado_total AS (
        SELECT e.e_sucursal, e.e_tipo, e.e_id, sum(e.e_cantidad) AS e_cantidad
          FROM esperado e
         GROUP BY 1, 2, 3
    ), registrado AS (
        -- Lo que el kardex descontó (venta, en negativo) y repuso (anulación) por esas ventas.
        SELECT m.sucursal_id AS r_sucursal,
               CASE WHEN m.ingrediente_id IS NOT NULL THEN 'materia_prima' ELSE 'producto' END::varchar AS r_tipo,
               COALESCE(m.ingrediente_id, m.producto_id) AS r_id,
               -sum(m.cantidad) AS r_cantidad
          FROM public.movimientos_stock m
          JOIN del_periodo dp ON dp.v_id = m.referencia_id
         WHERE m.referencia_tipo = 'venta'
           AND m.tipo_movimiento IN ('venta', 'anulacion_venta')
         GROUP BY 1, 2, 3
    ), cruce AS (
        SELECT COALESCE(e.e_sucursal, r.r_sucursal) AS c_sucursal,
               COALESCE(e.e_tipo, r.r_tipo) AS c_tipo,
               COALESCE(e.e_id, r.r_id) AS c_id,
               round(COALESCE(e.e_cantidad, 0), 3) AS c_esperado,
               round(COALESCE(r.r_cantidad, 0), 3) AS c_registrado
          FROM esperado_total e
          FULL JOIN registrado r
            ON r.r_sucursal IS NOT DISTINCT FROM e.e_sucursal
           AND r.r_tipo = e.e_tipo
           AND r.r_id = e.e_id
    )
    SELECT c.c_sucursal,
           COALESCE(s.nombre, 'Sin sucursal')::varchar,
           c.c_tipo,
           c.c_id,
           COALESCE(i.nombre, p.nombre)::varchar,
           CASE WHEN c.c_tipo = 'materia_prima' THEN um.abreviatura ELSE 'un' END::varchar,
           c.c_esperado,
           c.c_registrado,
           c.c_registrado - c.c_esperado,
           c.c_registrado = c.c_esperado
      FROM cruce c
      LEFT JOIN public.sucursales s ON s.id = c.c_sucursal
      LEFT JOIN public.ingredientes i ON c.c_tipo = 'materia_prima' AND i.id = c.c_id
      LEFT JOIN public.unidades_medida um ON um.id = i.unidad_id
      LEFT JOIN public.productos p ON c.c_tipo = 'producto' AND p.id = c.c_id
     -- Una línea en 0 contra 0 (venta anulada y repuesta, sin nada esperado) no aporta.
     WHERE NOT (c.c_esperado = 0 AND c.c_registrado = 0)
     ORDER BY c.c_registrado = c.c_esperado, c.c_sucursal IS NULL, s.nombre, COALESCE(i.nombre, p.nombre);
END;
$function$;

COMMENT ON FUNCTION public.fn_cuadratura_ventas_stock(integer[], date, date) IS
    'H4.1: por sucursal y artículo, lo que las ventas del período debieron descontar (productos sin receta o ingredientes de la receta usada) contra los movimientos venta y anulacion_venta de esas ventas.';

REVOKE ALL ON FUNCTION public.fn_cuadratura_ventas_stock(integer[], date, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_cuadratura_ventas_stock(integer[], date, date) TO nury_admin;

COMMIT;

NOTIFY pgrst, 'reload schema';


-- #####################################################################
-- 53. database/migrations/20261105_guardar_promocion.sql
-- #####################################################################

-- H5.2 — Guardar promociones desde Gestión de negocio (crear o editar con sus productos).
--
-- La pantalla de promociones (T02) quedó como maqueta: guardar y desactivar no escribían.
-- Una promoción y sus productos se tienen que guardar juntos (debe tener al menos un producto,
-- trigger diferido de 20261105_promociones.sql) y PostgREST hace una transacción por pedido;
-- por eso el guardado es una sola función:
--
--   fn_guardar_promocion(p_id, p_nombre, p_tipo, p_valor, p_sucursal_id, p_inicio, p_termino,
--                        p_productos) → id de la promoción
--     p_id         NULL = crear; un id = editar esa promoción.
--     p_productos  [{"producto_id": 1, "cantidad": 1}, ...]; al editar reemplaza los productos.
--   Valida con mensajes para la pantalla (22023) lo mismo que las restricciones de la tabla,
--   además de productos repetidos, inexistentes o inactivos. Al editar no cambia `activa` ni
--   las ventas ya hechas (guardan su propio precio y descuento, T07).
--
-- Desactivar no necesita función: es PATCH promociones?id=eq.X {"activa": false}, que el
-- administrador ya puede hacer (UPDATE) y el cajero no.
--
-- SECURITY INVOKER: corre con los permisos de quien la llama. El administrador escribe en
-- promociones y promocion_productos; el cajero y el bodeguero no pueden ni ejecutarla.
--
-- Requiere 20261105_promociones.sql y 20261012_permisos_cajero.sql (fn_usuario_actual_id).
-- Prueba: database/tests/guardar_promocion.sql.

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_guardar_promocion(
    p_id          INTEGER,
    p_nombre      TEXT,
    p_tipo        TEXT,
    p_valor       NUMERIC,
    p_sucursal_id INTEGER,
    p_inicio      TIMESTAMPTZ,
    p_termino     TIMESTAMPTZ,
    p_productos   JSONB
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, pg_temp
AS $function$
DECLARE
    v_id     INTEGER;
    v_nombre TEXT := btrim(COALESCE(p_nombre, ''));
    v_lineas INTEGER;
    v_texto  TEXT;
BEGIN
    IF v_nombre = '' OR length(v_nombre) > 120 THEN
        RAISE EXCEPTION 'Ingresa un nombre de hasta 120 caracteres.' USING ERRCODE = '22023';
    END IF;
    IF p_tipo IS NULL OR p_tipo NOT IN ('porcentaje', 'monto_fijo') THEN
        RAISE EXCEPTION 'El tipo de descuento debe ser porcentaje o monto fijo.' USING ERRCODE = '22023';
    END IF;
    IF p_valor IS NULL OR p_valor <= 0 THEN
        RAISE EXCEPTION 'El descuento debe ser mayor que 0.' USING ERRCODE = '22023';
    END IF;
    IF p_tipo = 'porcentaje' AND p_valor > 100 THEN
        RAISE EXCEPTION 'El porcentaje no puede ser mayor a 100.' USING ERRCODE = '22023';
    END IF;
    IF p_inicio IS NULL OR p_termino IS NULL THEN
        RAISE EXCEPTION 'Indica la fecha y hora de inicio y de término.' USING ERRCODE = '22023';
    END IF;
    IF p_termino <= p_inicio THEN
        RAISE EXCEPTION 'El término debe ser posterior al inicio.' USING ERRCODE = '22023';
    END IF;
    IF p_sucursal_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM public.sucursales WHERE id = p_sucursal_id) THEN
        RAISE EXCEPTION 'La sucursal elegida no existe.' USING ERRCODE = '22023';
    END IF;

    -- Productos: arreglo no vacío de {producto_id, cantidad > 0}, sin repetir.
    IF p_productos IS NULL OR jsonb_typeof(p_productos) <> 'array'
       OR jsonb_array_length(p_productos) = 0 THEN
        RAISE EXCEPTION 'Agrega al menos un producto.' USING ERRCODE = '22023';
    END IF;
    IF EXISTS (
        SELECT 1 FROM jsonb_array_elements(p_productos) e
         WHERE jsonb_typeof(e) <> 'object'
            OR jsonb_typeof(e -> 'producto_id') IS DISTINCT FROM 'number'
            OR jsonb_typeof(e -> 'cantidad') IS DISTINCT FROM 'number'
            OR (e ->> 'cantidad')::numeric <= 0
            OR (e ->> 'cantidad')::numeric <> trunc((e ->> 'cantidad')::numeric)
    ) THEN
        RAISE EXCEPTION 'Cada producto necesita una cantidad entera mayor que 0.' USING ERRCODE = '22023';
    END IF;

    SELECT count(*) INTO v_lineas FROM jsonb_array_elements(p_productos);
    IF v_lineas <> (SELECT count(DISTINCT (e ->> 'producto_id')::integer)
                      FROM jsonb_array_elements(p_productos) e) THEN
        RAISE EXCEPTION 'Un producto aparece más de una vez: ajusta su cantidad.' USING ERRCODE = '22023';
    END IF;

    SELECT string_agg(COALESCE(p.nombre, '#' || l.producto_id), ', ' ORDER BY l.producto_id)
      INTO v_texto
      FROM (SELECT (e ->> 'producto_id')::integer AS producto_id
              FROM jsonb_array_elements(p_productos) e) l
      LEFT JOIN public.productos p ON p.id = l.producto_id
     WHERE p.id IS NULL OR NOT p.activo;
    IF v_texto IS NOT NULL THEN
        RAISE EXCEPTION 'Estos productos no existen o están inactivos: %.', v_texto
            USING ERRCODE = '22023';
    END IF;

    -- Promoción -----------------------------------------------------------------------------
    IF p_id IS NULL THEN
        INSERT INTO public.promociones
            (nombre, tipo, valor_descuento, sucursal_id, inicio, termino, creado_por)
        VALUES
            (v_nombre, p_tipo, p_valor, p_sucursal_id, p_inicio, p_termino,
             public.fn_usuario_actual_id())
        RETURNING id INTO v_id;
    ELSE
        UPDATE public.promociones
           SET nombre          = v_nombre,
               tipo            = p_tipo,
               valor_descuento = p_valor,
               sucursal_id     = p_sucursal_id,
               inicio          = p_inicio,
               termino         = p_termino
         WHERE id = p_id
        RETURNING id INTO v_id;
        IF v_id IS NULL THEN
            RAISE EXCEPTION 'La promoción #% no existe.', p_id USING ERRCODE = 'P0002';
        END IF;
        DELETE FROM public.promocion_productos WHERE promocion_id = v_id;
    END IF;

    INSERT INTO public.promocion_productos (promocion_id, producto_id, cantidad)
        SELECT v_id, (e ->> 'producto_id')::integer, (e ->> 'cantidad')::integer
          FROM jsonb_array_elements(p_productos) e;

    RETURN v_id;
END;
$function$;

COMMENT ON FUNCTION public.fn_guardar_promocion(INTEGER, TEXT, TEXT, NUMERIC, INTEGER, TIMESTAMPTZ, TIMESTAMPTZ, JSONB) IS
    'Crea (p_id NULL) o edita una promoción con sus productos en una sola transacción (H5.2).';

REVOKE ALL ON FUNCTION public.fn_guardar_promocion(INTEGER, TEXT, TEXT, NUMERIC, INTEGER, TIMESTAMPTZ, TIMESTAMPTZ, JSONB)
    FROM PUBLIC, web_anon, nury_cajero, nury_bodeguero;
GRANT EXECUTE ON FUNCTION public.fn_guardar_promocion(INTEGER, TEXT, TEXT, NUMERIC, INTEGER, TIMESTAMPTZ, TIMESTAMPTZ, JSONB)
    TO nury_admin;

COMMIT;

NOTIFY pgrst, 'reload schema';


-- #####################################################################
-- 54. database/migrations/20261105_promociones.sql
-- #####################################################################

-- H5.2 T01 — Modelo de promociones: productos, tipo y monto de descuento, sucursal y ventana
-- de vigencia (fecha y hora de inicio y término).
--
-- Contexto: `promociones` y `promocion_productos` venían del esquema base (schema_nury.sql)
-- con otro modelo: vigencia por fechas (DATE) más un horario diario y días de la semana, y
-- los tipos precio_fijo y combo. Nada en la app ni en las funciones usa esas columnas; solo
-- detalle_venta.promocion_id y alertas_margen.promocion_id apuntan a la tabla. Por eso se
-- ajusta la tabla existente (ALTER) en vez de crear otra.
--
-- Modelo nuevo:
--   promociones
--     nombre            obligatorio, no vacío.
--     tipo              'porcentaje' | 'monto_fijo'. El combo (1 sándwich + 1 café) es una
--                       promoción con varios productos, no un tipo aparte.
--     valor_descuento   > 0; si es porcentaje, como máximo 100.
--     sucursal_id       sucursal donde rige; NULL = todas las sucursales.
--     inicio, termino   TIMESTAMPTZ. Rige desde `inicio` hasta `termino` (sin incluirlo):
--                       el sistema la aplica sola dentro de esa ventana, sin activarla a mano.
--                       termino > inicio.
--     activa            interruptor manual (se mantiene), además de la ventana.
--     prioridad, combinable_con_otras, creado_por, creado_en   sin cambios.
--   promocion_productos
--     cantidad          unidades del producto que forman la promoción (> 0, por defecto 1).
--   Al menos un producto por promoción: se revisa al terminar la transacción (trigger
--   diferido), así se puede crear la promoción y luego sus productos en la misma transacción.
--
-- Se eliminan fecha_inicio, fecha_fin, hora_inicio, hora_fin y dias_semana (reemplazadas por
-- inicio/termino). Si la tabla tiene filas que no se pueden convertir sin perder información
-- (horario diario, días de la semana, tipos precio_fijo/combo, sin productos o sin
-- descuento), la migración se detiene con el motivo y no cambia nada.
--
-- Permisos: el administrador crea y modifica; el cajero solo lee (aplica la promoción vigente
-- en la venta, H5.2); el bodeguero y web_anon no acceden.
--
-- ANTES DE APLICAR EN PRODUCCIÓN:
--   a) Revisar si hay promociones guardadas:
--        SELECT * FROM promociones;
--        SELECT * FROM promocion_productos;
--   b) Ejecutarlo como dueño de `promociones` (el mismo de `ventas`).
--   c) Correr database/tests/promociones.sql en una base de pruebas.
--   d) Después de aplicar: NOTIFY pgrst, 'reload schema'; (va al final del script).

BEGIN;

-- 1) Datos existentes: solo se convierten los que caben en el modelo nuevo --------------
-- Solo la primera vez (mientras existan las columnas viejas); volver a correr el script no
-- cambia nada.
ALTER TABLE public.promociones
    ADD COLUMN IF NOT EXISTS sucursal_id INTEGER REFERENCES public.sucursales(id),
    ADD COLUMN IF NOT EXISTS inicio      TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS termino     TIMESTAMPTZ;

DO $$
DECLARE
    v_ids TEXT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema = 'public' AND table_name = 'promociones'
                      AND column_name = 'fecha_inicio') THEN
        RETURN;
    END IF;

    EXECUTE $q$
        SELECT string_agg(id::text, ', ' ORDER BY id)
          FROM public.promociones p
         WHERE tipo NOT IN ('porcentaje', 'monto_fijo')
            OR valor_descuento IS NULL OR valor_descuento <= 0
            OR (tipo = 'porcentaje' AND valor_descuento > 100)
            OR hora_inicio IS NOT NULL OR hora_fin IS NOT NULL
            OR dias_semana IS NOT NULL
            OR btrim(nombre) = ''
            OR NOT EXISTS (SELECT 1 FROM public.promocion_productos pp WHERE pp.promocion_id = p.id)
    $q$ INTO v_ids;
    IF v_ids IS NOT NULL THEN
        RAISE EXCEPTION 'Promociones que no se pueden convertir al modelo nuevo: %', v_ids
            USING HINT = 'Tienen horario diario, días de la semana, tipo precio_fijo/combo, '
                         'descuento inválido o ningún producto. Revísalas a mano antes de migrar.';
    END IF;

    -- 2) Ventana de vigencia con fecha y hora. Las fechas viejas eran días completos en hora
    -- de Chile: desde las 00:00 del primero hasta las 00:00 del día siguiente al último.
    EXECUTE $q$
        UPDATE public.promociones
           SET inicio  = fecha_inicio::timestamp AT TIME ZONE 'America/Santiago',
               termino = (fecha_fin + 1)::timestamp AT TIME ZONE 'America/Santiago'
         WHERE inicio IS NULL
    $q$;
END $$;

ALTER TABLE public.promociones
    ALTER COLUMN inicio  SET NOT NULL,
    ALTER COLUMN termino SET NOT NULL,
    ALTER COLUMN valor_descuento SET NOT NULL,
    DROP COLUMN IF EXISTS fecha_inicio,   -- arrastra el CHECK (fecha_fin >= fecha_inicio)
    DROP COLUMN IF EXISTS fecha_fin,
    DROP COLUMN IF EXISTS hora_inicio,
    DROP COLUMN IF EXISTS hora_fin,
    DROP COLUMN IF EXISTS dias_semana;

-- 3) Tipo y validaciones -----------------------------------------------------------------
-- Se reemplaza el CHECK del tipo (nombre generado por PostgreSQL), igual que en 0007.
DO $$
DECLARE
    v_con TEXT;
BEGIN
    FOR v_con IN
        SELECT conname FROM pg_constraint
         WHERE conrelid = 'public.promociones'::regclass
           AND contype = 'c'
           AND pg_get_constraintdef(oid) ILIKE '%tipo%'
           AND conname NOT IN ('promociones_tipo_check', 'promociones_descuento_check')
    LOOP
        EXECUTE format('ALTER TABLE public.promociones DROP CONSTRAINT %I', v_con);
    END LOOP;
END $$;

ALTER TABLE public.promociones
    DROP CONSTRAINT IF EXISTS promociones_tipo_check,
    DROP CONSTRAINT IF EXISTS promociones_nombre_check,
    DROP CONSTRAINT IF EXISTS promociones_descuento_check,
    DROP CONSTRAINT IF EXISTS promociones_vigencia_check,
    ADD CONSTRAINT promociones_tipo_check
        CHECK (tipo IN ('porcentaje', 'monto_fijo')),
    ADD CONSTRAINT promociones_nombre_check
        CHECK (btrim(nombre) <> ''),
    ADD CONSTRAINT promociones_descuento_check
        CHECK (valor_descuento > 0 AND (tipo <> 'porcentaje' OR valor_descuento <= 100)),
    ADD CONSTRAINT promociones_vigencia_check
        CHECK (termino > inicio);

COMMENT ON TABLE public.promociones IS
    'Promociones programadas (H5.2): rigen solas entre inicio y termino, en una sucursal o en todas.';
COMMENT ON COLUMN public.promociones.tipo IS 'porcentaje o monto_fijo.';
COMMENT ON COLUMN public.promociones.valor_descuento IS 'Porcentaje (0-100] o monto en pesos, mayor que 0.';
COMMENT ON COLUMN public.promociones.sucursal_id IS 'Sucursal donde rige; NULL = todas las sucursales.';
COMMENT ON COLUMN public.promociones.inicio IS 'Desde cuándo rige (incluido).';
COMMENT ON COLUMN public.promociones.termino IS 'Hasta cuándo rige (no incluido). Posterior al inicio.';

-- Búsqueda de las promociones vigentes de una sucursal.
CREATE INDEX IF NOT EXISTS idx_promociones_sucursal_vigencia
    ON public.promociones(sucursal_id, inicio, termino);

-- 4) Productos de la promoción con su cantidad ---------------------------------------------
ALTER TABLE public.promocion_productos
    ADD COLUMN IF NOT EXISTS cantidad INTEGER NOT NULL DEFAULT 1;

ALTER TABLE public.promocion_productos
    DROP CONSTRAINT IF EXISTS promocion_productos_cantidad_check,
    ADD CONSTRAINT promocion_productos_cantidad_check CHECK (cantidad > 0);

COMMENT ON COLUMN public.promocion_productos.cantidad IS
    'Unidades del producto que forman la promoción (ej. 1 sándwich + 1 café).';

CREATE INDEX IF NOT EXISTS idx_promocion_productos_producto
    ON public.promocion_productos(producto_id);

-- 5) Al menos un producto por promoción ------------------------------------------------------
-- Diferido: se revisa al terminar la transacción, cuando ya se agregaron los productos.
CREATE OR REPLACE FUNCTION public.fn_promocion_con_productos()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $function$
DECLARE
    v_promocion_id INTEGER;
BEGIN
    -- IF y no CASE: PL/pgSQL revisa los campos de NEW/OLD de toda la expresión, y desde
    -- promociones OLD no tiene promocion_id ("record old has no field promocion_id").
    IF TG_TABLE_NAME = 'promociones' THEN
        v_promocion_id := NEW.id;
    ELSE
        v_promocion_id := OLD.promocion_id;
    END IF;
    -- Si se borró la promoción completa (ON DELETE CASCADE) no hay nada que revisar.
    IF EXISTS (SELECT 1 FROM public.promociones WHERE id = v_promocion_id)
       AND NOT EXISTS (SELECT 1 FROM public.promocion_productos WHERE promocion_id = v_promocion_id) THEN
        RAISE EXCEPTION 'La promoción #% debe tener al menos un producto', v_promocion_id
            USING ERRCODE = '23514';
    END IF;
    RETURN NULL;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_promocion_con_productos() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_promociones_con_productos ON public.promociones;
CREATE CONSTRAINT TRIGGER trg_promociones_con_productos
    AFTER INSERT ON public.promociones
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION public.fn_promocion_con_productos();

DROP TRIGGER IF EXISTS trg_promocion_productos_al_menos_uno ON public.promocion_productos;
CREATE CONSTRAINT TRIGGER trg_promocion_productos_al_menos_uno
    AFTER DELETE OR UPDATE OF promocion_id ON public.promocion_productos
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION public.fn_promocion_con_productos();

-- 6) Permisos ----------------------------------------------------------------------------------
REVOKE ALL ON public.promociones, public.promocion_productos FROM PUBLIC, web_anon, nury_bodeguero, nury_cajero;
GRANT SELECT ON public.promociones, public.promocion_productos TO nury_cajero;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.promociones, public.promocion_productos TO nury_admin;
GRANT USAGE ON SEQUENCE public.promociones_id_seq TO nury_admin;

COMMIT;

NOTIFY pgrst, 'reload schema';


-- #####################################################################
-- 55. database/migrations/20261105_promociones_margen.sql
-- #####################################################################

-- H5.2 T07 — Guardar en cada venta el descuento aplicado por promoción y el margen
-- sacrificado por producto.
--
-- Requiere 20261020_versiones_receta.sql (receta_version_id en detalle_venta),
-- 0006_facturas_compra_productos.sql (productos.precio_compra) y 20261105_promociones_venta.sql.
--
-- Cada línea de detalle_venta ya guardaba:
--   promocion_id      qué promoción se aplicó (NULL = sin promoción)
--   precio_lista      precio original del producto al vender
--   precio_unitario   precio final cobrado (con promoción lo calcula la base, T05)
-- Se agrega:
--   descuento_unitario   precio_lista − precio_unitario si la línea tiene promoción; 0 si no.
--                        Columna calculada (GENERATED): siempre coincide con los precios.
--   costo_unitario       costo del producto al momento de la venta, guardado como foto:
--                          con receta  Σ cantidad × costo promedio del ingrediente, de la
--                                      versión de receta con que se descontó (H2.5);
--                          reventa     último costo de compra (productos.precio_compra);
--                          NULL si no hay costo registrado (o en ventas anteriores a esta
--                          migración).
--   margen_sacrificado   margen que se dejó de ganar por la promoción en la línea:
--                          (precio_lista − costo) × cantidad − (precio_unitario − costo) × cantidad
--                        = descuento_unitario × cantidad. No depende del costo (es el mismo
--                        con y sin promoción), así que existe aunque costo_unitario sea NULL.
--                        Columna calculada (GENERATED).
-- Con costo_unitario los reportes también pueden mostrar el margen ganado:
--   (precio_unitario − costo_unitario) × cantidad (negativo = vendido bajo costo).
--
-- trg_detalle_venta_valorizar (BEFORE INSERT) completa costo_unitario. Corre después de
-- trg_detalle_venta_receta_version (los BEFORE corren en orden alfabético), así usa la versión
-- de receta ya fijada.
--
-- ANTES DE APLICAR EN PRODUCCIÓN:
--   a) Ejecutarlo como dueño de detalle_venta. Agregar columnas GENERATED reescribe la tabla:
--      aplicarlo fuera del horario de venta.
--   b) Correr database/tests/promociones_margen.sql en una base de pruebas.
--   c) Después de aplicar: NOTIFY pgrst, 'reload schema'; (va al final del script).

BEGIN;

ALTER TABLE public.detalle_venta
    ADD COLUMN IF NOT EXISTS costo_unitario NUMERIC(12,2),
    ADD COLUMN IF NOT EXISTS descuento_unitario NUMERIC(12,2)
        GENERATED ALWAYS AS (
            CASE WHEN promocion_id IS NULL THEN 0 ELSE precio_lista - precio_unitario END
        ) STORED,
    ADD COLUMN IF NOT EXISTS margen_sacrificado NUMERIC(12,2)
        GENERATED ALWAYS AS (
            CASE WHEN promocion_id IS NULL THEN 0 ELSE (precio_lista - precio_unitario) * cantidad END
        ) STORED;

COMMENT ON COLUMN public.detalle_venta.precio_lista IS 'Precio original del producto al vender.';
COMMENT ON COLUMN public.detalle_venta.precio_unitario IS 'Precio final cobrado por unidad (con promoción lo calcula la base).';
COMMENT ON COLUMN public.detalle_venta.descuento_unitario IS
    'Descuento por unidad de la promoción (precio_lista − precio_unitario); 0 sin promoción (H5.2 T07).';
COMMENT ON COLUMN public.detalle_venta.costo_unitario IS
    'Costo por unidad al vender: receta (costo promedio de ingredientes) o último costo de compra; NULL si no hay costo (H5.2 T07).';
COMMENT ON COLUMN public.detalle_venta.margen_sacrificado IS
    'Margen que se dejó de ganar por la promoción en la línea: descuento_unitario × cantidad (H5.2 T07).';

-- Costo del producto al momento de la venta ------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_detalle_venta_valorizar()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $function$
BEGIN
    IF NEW.receta_version_id IS NOT NULL THEN
        SELECT ROUND(SUM(r.cantidad_necesaria * i.costo_unitario_promedio), 2)
          INTO NEW.costo_unitario
          FROM public.recetas_version_detalle r
          JOIN public.ingredientes i ON i.id = r.ingrediente_id
         WHERE r.version_id = NEW.receta_version_id;
    ELSE
        SELECT p.precio_compra INTO NEW.costo_unitario
          FROM public.productos p WHERE p.id = NEW.producto_id;
    END IF;
    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_detalle_venta_valorizar() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_detalle_venta_valorizar ON public.detalle_venta;
CREATE TRIGGER trg_detalle_venta_valorizar
    BEFORE INSERT ON public.detalle_venta
    FOR EACH ROW EXECUTE FUNCTION public.fn_detalle_venta_valorizar();

-- Consultas de los reportes de promociones (H5.2): líneas con promoción.
CREATE INDEX IF NOT EXISTS idx_detalle_venta_promocion
    ON public.detalle_venta(promocion_id) WHERE promocion_id IS NOT NULL;

COMMIT;

NOTIFY pgrst, 'reload schema';


-- #####################################################################
-- 56. database/migrations/20261105_promociones_permisos.sql
-- #####################################################################

-- H5.2 T03 — Promociones por rol: el cajero solo aplica promociones vigentes y no puede
-- crearlas ni cambiar su descuento o vigencia.
--
-- Requiere 20261012_permisos_cajero.sql (fn_usuario_actual_id) y 20261105_promociones.sql.
--
-- Escritura: solo el administrador (INSERT/UPDATE/DELETE). El cajero no tiene esos permisos
-- (ya en 20261105_promociones.sql; aquí se reafirma).
--
-- Lectura con RLS, igual que ventas y detalle_venta (20261012_permisos_cajero.sql):
--   promociones          admin: todas.
--                        cajero: solo las activas, dentro de su ventana (inicio <= ahora <
--                        termino) y de su sucursal o de todas (sucursal_id NULL). Una
--                        programada o terminada no existe para él: no la puede aplicar.
--   promocion_productos  admin: todos. cajero: solo los de las promociones que puede ver.
-- La ventana se evalúa con now() en cada consulta: nadie tiene que activarla ni apagarla.
--
-- fn_sucursal_actual_id(): sucursal del usuario de la sesión. SECURITY DEFINER porque el
-- cajero no lee la tabla usuarios.
--
-- Las funciones SECURITY DEFINER del dueño de las tablas (registro de ventas, reportes) no
-- quedan limitadas: el dueño no pasa por RLS (no se usa FORCE ROW LEVEL SECURITY).
--
-- ANTES DE APLICAR EN PRODUCCIÓN:
--   a) Ejecutarlo como dueño de `promociones`.
--   b) Correr database/tests/promociones_permisos.sql en una base de pruebas.
--   c) Después de aplicar: NOTIFY pgrst, 'reload schema'; (va al final del script).

BEGIN;

-- Sucursal del usuario de la sesión ---------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_sucursal_actual_id()
RETURNS INTEGER
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT u.sucursal_id FROM public.usuarios u WHERE u.id = public.fn_usuario_actual_id();
$$;

REVOKE ALL ON FUNCTION public.fn_sucursal_actual_id() FROM PUBLIC, web_anon, nury_bodeguero;
GRANT EXECUTE ON FUNCTION public.fn_sucursal_actual_id() TO nury_admin, nury_cajero;

-- Escritura solo del administrador -------------------------------------------------------------
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.promociones, public.promocion_productos
    FROM PUBLIC, web_anon, nury_cajero, nury_bodeguero;
REVOKE ALL ON public.promociones, public.promocion_productos FROM nury_bodeguero, web_anon;
GRANT SELECT ON public.promociones, public.promocion_productos TO nury_cajero;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.promociones, public.promocion_productos TO nury_admin;

-- Lectura por fila ------------------------------------------------------------------------------
ALTER TABLE public.promociones ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.promocion_productos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS promociones_admin ON public.promociones;
CREATE POLICY promociones_admin ON public.promociones TO nury_admin
    USING (TRUE) WITH CHECK (TRUE);

DROP POLICY IF EXISTS promociones_cajero_vigentes ON public.promociones;
CREATE POLICY promociones_cajero_vigentes ON public.promociones FOR SELECT TO nury_cajero
    USING (
        activa
        AND inicio <= now() AND now() < termino
        AND (sucursal_id IS NULL OR sucursal_id = (SELECT public.fn_sucursal_actual_id()))
    );

DROP POLICY IF EXISTS promocion_productos_admin ON public.promocion_productos;
CREATE POLICY promocion_productos_admin ON public.promocion_productos TO nury_admin
    USING (TRUE) WITH CHECK (TRUE);

-- La subconsulta pasa por la política de promociones: solo las vigentes de su sucursal.
DROP POLICY IF EXISTS promocion_productos_cajero_vigentes ON public.promocion_productos;
CREATE POLICY promocion_productos_cajero_vigentes ON public.promocion_productos FOR SELECT TO nury_cajero
    USING (EXISTS (SELECT 1 FROM public.promociones p WHERE p.id = promocion_id));

COMMIT;

NOTIFY pgrst, 'reload schema';


-- #####################################################################
-- 57. database/migrations/20261105_promociones_venta.sql
-- #####################################################################

-- H5.2 T05 — Aplicar las promociones vigentes al momento de la venta.
--
-- Requiere 0005_venta_empleado_descuento.sql (firma actual de fn_registrar_venta),
-- 20261105_promociones.sql y 20261105_promociones_vigentes.sql.
--
-- Hasta ahora fn_registrar_venta guardaba el promocion_id y el precio_unitario que enviaba
-- el POS sin revisarlos: con la API se podía inventar un descuento. Desde esta migración, en
-- las líneas con promocion_id el precio lo calcula la base y el del POS se ignora:
--
--   - La promoción debe estar vigente en la sucursal de la venta en este momento
--     (fn_promociones_vigentes, hora del servidor). Si terminó o se desactivó, la venta se
--     rechaza con el motivo y no se guarda nada.
--   - El producto debe ser parte de la promoción.
--   - La promoción debe venir completa: cada producto en su cantidad (1 sándwich + 1 café),
--     o en múltiplos iguales si se aplicó varias veces (2 + 2). Un combo a medias no lleva
--     descuento.
--   - Precio de cada unidad (fn_precios_promocion, el POS usa la misma regla para mostrarlo):
--       porcentaje  precio de lista × (100 − %) / 100, redondeado a pesos.
--       monto_fijo  el monto (como máximo el valor de la promoción) se reparte entre los
--                   productos según su precio de lista, redondeado a pesos; lo que sobra o
--                   falta por redondeo va al producto más caro con cantidad 1, para que la
--                   promoción descuente exactamente el monto. Nunca queda bajo $0.
--
-- detalle_venta conserva precio_lista (precio normal) y precio_unitario (cobrado), así que el
-- descuento de cada línea queda registrado para los reportes de H5.2. Cada producto de la
-- promoción es una línea propia: el inventario se descuenta con la receta (o unidades) de
-- cada uno, igual que una venta normal (fn_aplicar_venta).
--
-- Las líneas sin promoción y la venta a empleado no cambian: mismo comportamiento de 0005.
-- El 30% de la venta a empleado se calcula sobre el total ya con promociones.
--
-- ANTES DE APLICAR EN PRODUCCIÓN:
--   a) Ejecutarlo como superusuario o como nury_admin (la función es de nury_admin).
--   b) Correr database/tests/promociones_venta.sql y database/tests/venta_empleado.sql en una
--      base de pruebas.
--   c) Después de aplicar: NOTIFY pgrst, 'reload schema'; (va al final del script).

BEGIN;

-- La función original es de nury_admin: se recrea con ese mismo dueño.
SET LOCAL ROLE nury_admin;

-- 1) Precio de cada producto en una aplicación de la promoción --------------------------------
CREATE OR REPLACE FUNCTION public.fn_precios_promocion(p_promocion_id INTEGER)
RETURNS TABLE (producto_id INTEGER, cantidad INTEGER, precio_lista NUMERIC, precio_unitario NUMERIC)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, public, pg_temp
AS $function$
    WITH promo AS (
        SELECT p.tipo, p.valor_descuento AS valor FROM public.promociones p WHERE p.id = p_promocion_id
    ), base AS (
        SELECT pp.producto_id, pp.cantidad, pr.precio_venta AS precio
          FROM public.promocion_productos pp
          JOIN public.productos pr ON pr.id = pp.producto_id
         WHERE pp.promocion_id = p_promocion_id
    ), total AS (
        -- Valor de la promoción a precio de lista; el monto fijo no puede pasar de ahí.
        SELECT COALESCE(SUM(b.precio * b.cantidad), 0) AS valor FROM base b
    ), descuentos AS (
        SELECT b.producto_id, b.cantidad, b.precio,
               CASE
                   WHEN promo.tipo = 'porcentaje'
                       THEN b.precio - ROUND(b.precio * (100 - promo.valor) / 100, 0)
                   WHEN total.valor > 0
                       THEN ROUND(LEAST(promo.valor, total.valor) * b.precio / total.valor, 0)
                   ELSE 0
               END AS descuento
          FROM base b, promo, total
    ), resto AS (
        -- Monto fijo: lo que el redondeo dejó sin repartir (puede ser negativo).
        SELECT CASE
                   WHEN promo.tipo = 'monto_fijo' AND total.valor > 0
                       THEN LEAST(promo.valor, total.valor) - COALESCE(SUM(d.descuento * d.cantidad), 0)
                   ELSE 0
               END AS valor
          FROM promo, total
          LEFT JOIN descuentos d ON TRUE
         GROUP BY promo.tipo, promo.valor, total.valor
    ), ajustado AS (
        -- Recibe el resto el producto más caro con cantidad 1 (si no hay, se omite el ajuste).
        SELECT d.producto_id FROM descuentos d
         WHERE d.cantidad = 1
         ORDER BY d.precio DESC, d.producto_id
         LIMIT 1
    )
    SELECT d.producto_id, d.cantidad, d.precio,
           GREATEST(
               d.precio - LEAST(
                   d.descuento + CASE WHEN d.producto_id = (SELECT a.producto_id FROM ajustado a)
                                      THEN COALESCE((SELECT r.valor FROM resto r), 0) ELSE 0 END,
                   d.precio),
               0)
      FROM descuentos d
     ORDER BY d.producto_id;
$function$;

COMMENT ON FUNCTION public.fn_precios_promocion(INTEGER) IS
    'Precio de lista y precio con descuento de cada producto en una aplicación de la promoción (H5.2 T05). Interna de fn_registrar_venta.';

REVOKE ALL ON FUNCTION public.fn_precios_promocion(INTEGER) FROM PUBLIC, web_anon, nury_cajero, nury_bodeguero;

-- 2) Registro de la venta con promociones calculadas en la base ------------------------------
-- Misma firma que 0005: se reemplaza el cuerpo y se conservan los permisos.
CREATE OR REPLACE FUNCTION public.fn_registrar_venta(
    p_sucursal_id INTEGER,
    p_cajero_id INTEGER,
    p_medio_pago CHARACTER VARYING,
    p_items JSONB,
    p_tipo_venta CHARACTER VARYING DEFAULT 'normal',
    p_empleado_id INTEGER DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'pg_catalog', 'public', 'pg_temp'
AS $function$
DECLARE
    -- Descuento fijo de venta a empleado (H2.12). Por ahora no es editable.
    c_descuento_empleado CONSTANT NUMERIC(5,2) := 30;

    v_venta_id      INTEGER;
    v_turno_id      INTEGER;
    v_tipo_venta    VARCHAR(20) := COALESCE(p_tipo_venta, 'normal');
    item            JSONB;
    v_producto_id   INTEGER;
    v_precio_lista  NUMERIC(12,2);
    v_precio_final  NUMERIC(12,2);
    v_promocion_id  INTEGER;
    v_cantidad      NUMERIC(12,3);
    v_subtotal      NUMERIC(12,2);
    v_descuento     NUMERIC(12,2);
    v_incompleta    TEXT;
BEGIN
    IF jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'La venta no tiene productos';
    END IF;

    IF v_tipo_venta NOT IN ('normal', 'empleado') THEN
        RAISE EXCEPTION 'Tipo de venta no válido: %', v_tipo_venta
            USING ERRCODE = '22023';
    END IF;

    IF v_tipo_venta = 'empleado' THEN
        IF p_empleado_id IS NULL THEN
            RAISE EXCEPTION 'Debes indicar el empleado que compra'
                USING ERRCODE = '22023';
        END IF;

        IF NOT EXISTS (
            SELECT 1 FROM public.usuarios WHERE id = p_empleado_id AND activo = TRUE
        ) THEN
            RAISE EXCEPTION 'El empleado no existe o está deshabilitado'
                USING ERRCODE = '22023';
        END IF;
    ELSIF p_empleado_id IS NOT NULL THEN
        RAISE EXCEPTION 'Una venta normal no lleva empleado'
            USING ERRCODE = '22023';
    END IF;

    SELECT id INTO v_turno_id
      FROM public.turnos
     WHERE usuario_id = p_cajero_id
       AND sucursal_id = p_sucursal_id
       AND hora_fin IS NULL
     ORDER BY hora_inicio DESC
     LIMIT 1;

    IF v_turno_id IS NULL THEN
        RAISE EXCEPTION 'No hay un turno activo para este cajero en esta sucursal; debes abrir turno antes de vender'
            USING ERRCODE = '28000';
    END IF;

    INSERT INTO ventas (sucursal_id, cajero_id, medio_pago, turno_id, tipo_venta, empleado_id)
    VALUES (p_sucursal_id, p_cajero_id, p_medio_pago, v_turno_id, v_tipo_venta, p_empleado_id)
    RETURNING id INTO v_venta_id;

    FOR item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        SELECT id, precio_venta INTO v_producto_id, v_precio_lista
          FROM productos
         WHERE nombre = item->>'producto' AND activo = TRUE;

        IF v_producto_id IS NULL THEN
            RAISE EXCEPTION 'Producto no encontrado o inactivo: %', item->>'producto';
        END IF;

        v_cantidad     := (item->>'cantidad')::NUMERIC;
        v_promocion_id := NULLIF(item->>'promocion_id', '')::INTEGER;

        IF v_promocion_id IS NULL THEN
            v_precio_final := COALESCE((item->>'precio_unitario')::NUMERIC, v_precio_lista);
        ELSE
            -- H5.2 T05: con promoción, el precio lo calcula la base; el del POS se ignora.
            IF NOT EXISTS (
                SELECT 1 FROM public.fn_promociones_vigentes(p_sucursal_id) v WHERE v.id = v_promocion_id
            ) THEN
                RAISE EXCEPTION 'La promoción #% no está vigente en esta sucursal: la venta no se registró', v_promocion_id
                    USING ERRCODE = '22023';
            END IF;

            SELECT pp.precio_unitario INTO v_precio_final
              FROM public.fn_precios_promocion(v_promocion_id) pp
             WHERE pp.producto_id = v_producto_id;
            IF NOT FOUND THEN
                RAISE EXCEPTION 'El producto % no es parte de la promoción #%', item->>'producto', v_promocion_id
                    USING ERRCODE = '22023';
            END IF;
        END IF;

        INSERT INTO detalle_venta (venta_id, producto_id, promocion_id, cantidad, precio_lista, precio_unitario)
        VALUES (v_venta_id, v_producto_id, v_promocion_id, v_cantidad, v_precio_lista, v_precio_final);
    END LOOP;

    -- H5.2 T05: cada promoción completa, con sus productos en múltiplos iguales.
    WITH vendidas AS (
        SELECT d.promocion_id, d.producto_id, SUM(d.cantidad) AS vendida
          FROM detalle_venta d
         WHERE d.venta_id = v_venta_id AND d.promocion_id IS NOT NULL
         GROUP BY d.promocion_id, d.producto_id
    ), esperadas AS (
        SELECT pp.promocion_id, pp.producto_id, pp.cantidad
          FROM promocion_productos pp
         WHERE pp.promocion_id IN (SELECT promocion_id FROM vendidas)
    ), comparadas AS (
        SELECT COALESCE(v.promocion_id, e.promocion_id) AS promocion_id,
               v.vendida / NULLIF(e.cantidad, 0) AS veces
          FROM vendidas v
          FULL JOIN esperadas e
            ON e.promocion_id = v.promocion_id AND e.producto_id = v.producto_id
    )
    SELECT string_agg(p.nombre, ', ') INTO v_incompleta
      FROM (
        SELECT c.promocion_id
          FROM comparadas c
         GROUP BY c.promocion_id
        HAVING bool_or(c.veces IS NULL OR c.veces <> trunc(c.veces) OR c.veces < 1)
            OR COUNT(DISTINCT c.veces) > 1
      ) malas
      JOIN promociones p ON p.id = malas.promocion_id;

    IF v_incompleta IS NOT NULL THEN
        RAISE EXCEPTION 'Promoción incompleta: %. Agrega todos sus productos en sus cantidades', v_incompleta
            USING ERRCODE = '22023';
    END IF;

    -- El trigger trg_actualizar_total_venta ya dejó total = suma de los
    -- subtotales. En una venta a empleado se descuenta el 30% sobre ese
    -- total, redondeado a pesos.
    IF v_tipo_venta = 'empleado' THEN
        SELECT COALESCE(SUM(subtotal), 0) INTO v_subtotal
          FROM detalle_venta
         WHERE venta_id = v_venta_id;

        v_descuento := ROUND(v_subtotal * c_descuento_empleado / 100, 0);

        UPDATE ventas
           SET descuento_porcentaje = c_descuento_empleado,
               descuento_monto      = v_descuento,
               total                = v_subtotal - v_descuento
         WHERE id = v_venta_id;
    END IF;

    RETURN v_venta_id;
END;
$function$;

COMMIT;

NOTIFY pgrst, 'reload schema';


-- #####################################################################
-- 58. database/migrations/20261105_promociones_vigentes.sql
-- #####################################################################

-- H5.2 T04 — Las promociones se aplican solas dentro de su ventana de vigencia y dejan de
-- aplicarse apenas terminan.
--
-- Requiere 20261105_promociones.sql y 20261105_promociones_permisos.sql.
--
-- fn_promociones_vigentes(p_sucursal_id, p_momento DEFAULT now()): las promociones que se
-- aplican en ese momento en la sucursal: activas, inicio <= momento < termino, y de esa
-- sucursal o de todas (sucursal_id NULL). Es la única regla de vigencia: la usan el POS (por
-- PostgREST) y la usará el registro de la venta.
--
-- Sin intervención manual: la hora la pone el servidor (now()), no el reloj del equipo del
-- cajero. Una promoción del sábado 00:00 al domingo 23:59 empieza y termina a esas horas
-- aunque nadie entre al sistema.
--
-- Zona horaria de Chile: inicio y termino son TIMESTAMPTZ (instantes absolutos), así que la
-- comparación no depende del TimeZone del servidor ni de la sesión. La pantalla convierte la
-- fecha y hora que escribe el administrador desde la hora de Chile (America/Santiago, con
-- horario de verano) al guardar, y la muestra en esa misma zona.
--
-- SECURITY INVOKER: para el cajero sigue mandando la RLS de 20261105_promociones_permisos.sql
-- (solo ve las de su sucursal, sea cual sea p_sucursal_id). p_momento permite consultar otro
-- instante (pruebas y reportes); el POS no lo envía.
--
-- ANTES DE APLICAR EN PRODUCCIÓN:
--   a) Ejecutarlo como dueño de `promociones`.
--   b) Correr database/tests/promociones_vigentes.sql en una base de pruebas.
--   c) Después de aplicar: NOTIFY pgrst, 'reload schema'; (va al final del script).

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_promociones_vigentes(
    p_sucursal_id INTEGER,
    p_momento     TIMESTAMPTZ DEFAULT now()
)
RETURNS SETOF public.promociones
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
    SELECT p.*
      FROM public.promociones p
     WHERE p.activa
       AND p.inicio <= p_momento
       AND p_momento < p.termino
       AND (p.sucursal_id IS NULL OR p.sucursal_id = p_sucursal_id)
     ORDER BY p.prioridad DESC, p.id;
$$;

COMMENT ON FUNCTION public.fn_promociones_vigentes(INTEGER, TIMESTAMPTZ) IS
    'Promociones que se aplican en ese momento (por defecto ahora, hora del servidor) en la sucursal: activas, inicio <= momento < termino, de la sucursal o de todas (H5.2 T04).';

REVOKE ALL ON FUNCTION public.fn_promociones_vigentes(INTEGER, TIMESTAMPTZ) FROM PUBLIC, web_anon, nury_bodeguero;
GRANT EXECUTE ON FUNCTION public.fn_promociones_vigentes(INTEGER, TIMESTAMPTZ) TO nury_admin, nury_cajero;

COMMIT;

NOTIFY pgrst, 'reload schema';


-- #####################################################################
-- 59. database/migrations/20261105_reporte_promociones.sql
-- #####################################################################

-- H5.2 T08 — Reportes: cuánto se vendió con descuento por promoción y cuánto margen se
-- sacrificó, por período y por producto.
--
-- Requiere 20261105_promociones_margen.sql (detalle_venta.margen_sacrificado y costo_unitario).
--
-- Funciones nuevas, sin cambiar las de H4.1 (20261104_reporte_*.sql). Mismas reglas que esas:
--   - p_sucursales: ids a incluir; NULL = todas.
--   - p_desde / p_hasta: días en hora de Chile, ambos incluidos; como máximo un año.
--   - Sin ventas anuladas.
--   - Los límites del período se pasan a la zona de ventas.fecha_venta (TIMESTAMP sin zona en
--     la hora del servidor) para usar el índice (sucursal_id, fecha_venta).
--   - Solo lectura (STABLE), SECURITY DEFINER, solo para el administrador.
--
-- Montos por línea (detalle_venta.subtotal, lo cobrado por los productos). El 30% de la venta
-- a empleado no es una promoción y no se cuenta aquí: va en los reportes de H4.1.
--
-- fn_reporte_promociones_periodo: una fila por día del período (también los días sin ventas,
-- en 0, igual que H4.2 T03), para verlo separado por día, semana o mes en el front.
--   vendido            total vendido en el día
--   vendido_con_descuento   lo vendido en líneas con promoción (precio final)
--   precio_lista_con_descuento  lo mismo a precio original
--   unidades_con_descuento, ventas_con_promocion (ventas con al menos una línea con promoción)
--   margen_sacrificado lo que la promoción dejó de ganar (Σ detalle_venta.margen_sacrificado)
--
-- fn_reporte_promociones_producto: una fila por producto vendido en el período (todas las
-- sucursales pedidas juntas), con o sin promoción, para reutilizar en Rendimiento por producto
-- (H4.4).
--   unidades, vendido                       todo lo vendido del producto
--   unidades_con_descuento, vendido_con_descuento, precio_lista_con_descuento
--   margen_sacrificado
--   margen_con_descuento   margen ganado en las líneas con promoción, solo las que tienen costo
--                          (Σ (precio final − costo) × cantidad); NULL si ninguna tiene costo.
--                          Negativo = se vendió bajo costo.
--   promociones            nombres de las promociones con que se vendió, separados por coma
--
-- ANTES DE APLICAR EN PRODUCCIÓN:
--   a) Ejecutarlo como dueño de ventas (como 20261104_reporte_ventas_sucursal.sql).
--   b) Correr database/tests/reporte_promociones.sql en una base de pruebas.
--   c) Después de aplicar: NOTIFY pgrst, 'reload schema'; (va al final del script).

BEGIN;

-- Por día -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_reporte_promociones_periodo(
    p_sucursales INTEGER[],
    p_desde      DATE,
    p_hasta      DATE
)
RETURNS TABLE (
    dia                        DATE,
    vendido                    NUMERIC,
    vendido_con_descuento      NUMERIC,
    precio_lista_con_descuento NUMERIC,
    unidades_con_descuento     NUMERIC,
    ventas_con_promocion       INTEGER,
    margen_sacrificado         NUMERIC
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $function$
DECLARE
    v_desde TIMESTAMP;
    v_hasta TIMESTAMP;
BEGIN
    IF p_desde IS NULL OR p_hasta IS NULL THEN
        RAISE EXCEPTION 'Indica la fecha inicial y la final del período' USING ERRCODE = '22023';
    END IF;
    IF p_desde > p_hasta THEN
        RAISE EXCEPTION 'La fecha inicial no puede ser posterior a la final' USING ERRCODE = '22023';
    END IF;
    IF p_hasta - p_desde > 366 THEN
        RAISE EXCEPTION 'El período no puede superar un año' USING ERRCODE = '22023';
    END IF;

    v_desde := (p_desde::timestamp AT TIME ZONE 'America/Santiago') AT TIME ZONE current_setting('TimeZone');
    v_hasta := ((p_hasta + 1)::timestamp AT TIME ZONE 'America/Santiago') AT TIME ZONE current_setting('TimeZone');

    RETURN QUERY
    WITH lineas AS (
        SELECT ((v.fecha_venta AT TIME ZONE current_setting('TimeZone')) AT TIME ZONE 'America/Santiago')::date AS l_dia,
               v.id AS l_venta, d.promocion_id AS l_promocion, d.cantidad AS l_cantidad,
               d.subtotal AS l_subtotal, d.precio_lista AS l_lista, d.margen_sacrificado AS l_margen
          FROM public.ventas v
          JOIN public.detalle_venta d ON d.venta_id = v.id
         WHERE NOT v.anulada
           AND v.fecha_venta >= v_desde
           AND v.fecha_venta <  v_hasta
           AND (p_sucursales IS NULL OR v.sucursal_id = ANY (p_sucursales))
    ), dias AS (
        SELECT g::date AS d_dia FROM generate_series(p_desde, p_hasta, interval '1 day') g
    )
    SELECT d.d_dia,
           COALESCE(sum(l.l_subtotal), 0),
           COALESCE(sum(l.l_subtotal) FILTER (WHERE l.l_promocion IS NOT NULL), 0),
           COALESCE(sum(l.l_lista * l.l_cantidad) FILTER (WHERE l.l_promocion IS NOT NULL), 0),
           COALESCE(sum(l.l_cantidad) FILTER (WHERE l.l_promocion IS NOT NULL), 0),
           (count(DISTINCT l.l_venta) FILTER (WHERE l.l_promocion IS NOT NULL))::int,
           COALESCE(sum(l.l_margen), 0)
      FROM dias d
      LEFT JOIN lineas l ON l.l_dia = d.d_dia
     GROUP BY d.d_dia
     ORDER BY d.d_dia;
END;
$function$;

COMMENT ON FUNCTION public.fn_reporte_promociones_periodo(integer[], date, date) IS
    'H5.2 T08: por día (hora de Chile), lo vendido con descuento por promoción y el margen sacrificado; días sin ventas en 0, sin anuladas.';

REVOKE ALL ON FUNCTION public.fn_reporte_promociones_periodo(integer[], date, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_reporte_promociones_periodo(integer[], date, date) TO nury_admin;

-- Por producto ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_reporte_promociones_producto(
    p_sucursales INTEGER[],
    p_desde      DATE,
    p_hasta      DATE
)
RETURNS TABLE (
    producto_id                INTEGER,
    producto                   VARCHAR,
    categoria                  VARCHAR,
    unidades                   NUMERIC,
    vendido                    NUMERIC,
    unidades_con_descuento     NUMERIC,
    vendido_con_descuento      NUMERIC,
    precio_lista_con_descuento NUMERIC,
    margen_sacrificado         NUMERIC,
    margen_con_descuento       NUMERIC,
    promociones                TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $function$
DECLARE
    v_desde TIMESTAMP;
    v_hasta TIMESTAMP;
BEGIN
    IF p_desde IS NULL OR p_hasta IS NULL THEN
        RAISE EXCEPTION 'Indica la fecha inicial y la final del período' USING ERRCODE = '22023';
    END IF;
    IF p_desde > p_hasta THEN
        RAISE EXCEPTION 'La fecha inicial no puede ser posterior a la final' USING ERRCODE = '22023';
    END IF;
    IF p_hasta - p_desde > 366 THEN
        RAISE EXCEPTION 'El período no puede superar un año' USING ERRCODE = '22023';
    END IF;

    v_desde := (p_desde::timestamp AT TIME ZONE 'America/Santiago') AT TIME ZONE current_setting('TimeZone');
    v_hasta := ((p_hasta + 1)::timestamp AT TIME ZONE 'America/Santiago') AT TIME ZONE current_setting('TimeZone');

    RETURN QUERY
    SELECT d.producto_id,
           p.nombre::varchar,
           p.categoria::varchar,
           sum(d.cantidad),
           sum(d.subtotal),
           COALESCE(sum(d.cantidad) FILTER (WHERE d.promocion_id IS NOT NULL), 0),
           COALESCE(sum(d.subtotal) FILTER (WHERE d.promocion_id IS NOT NULL), 0),
           COALESCE(sum(d.precio_lista * d.cantidad) FILTER (WHERE d.promocion_id IS NOT NULL), 0),
           sum(d.margen_sacrificado),
           sum((d.precio_unitario - d.costo_unitario) * d.cantidad)
               FILTER (WHERE d.promocion_id IS NOT NULL AND d.costo_unitario IS NOT NULL),
           string_agg(DISTINCT pr.nombre, ', ')
      FROM public.ventas v
      JOIN public.detalle_venta d ON d.venta_id = v.id
      JOIN public.productos p ON p.id = d.producto_id
      LEFT JOIN public.promociones pr ON pr.id = d.promocion_id
     WHERE NOT v.anulada
       AND v.fecha_venta >= v_desde
       AND v.fecha_venta <  v_hasta
       AND (p_sucursales IS NULL OR v.sucursal_id = ANY (p_sucursales))
     GROUP BY d.producto_id, p.nombre, p.categoria
     ORDER BY sum(d.margen_sacrificado) DESC, sum(d.subtotal) DESC, p.nombre;
END;
$function$;

COMMENT ON FUNCTION public.fn_reporte_promociones_producto(integer[], date, date) IS
    'H5.2 T08: por producto, cuánto se vendió con descuento por promoción, el margen sacrificado y el margen ganado con descuento; sin anuladas. Pensada para reutilizar en H4.4.';

REVOKE ALL ON FUNCTION public.fn_reporte_promociones_producto(integer[], date, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_reporte_promociones_producto(integer[], date, date) TO nury_admin;

COMMIT;

NOTIFY pgrst, 'reload schema';


-- #####################################################################
-- 60. database/migrations/20261106_costo_actual_productos.sql
-- #####################################################################

-- H4.4 T03 - Costo actual de cada producto para el margen del reporte de productos.
--
-- Decisión (06-11): el margen se calcula con el costo ACTUAL, no con el del día de la venta.
-- fn_costo_actual_productos() devuelve, por producto:
--   - con receta (tabla recetas = receta vigente): suma de cantidad_necesaria ×
--     ingredientes.costo_unitario_promedio (costo promedio ponderado de las compras), igual
--     que v_costo_producto y la alerta de margen de las promociones. origen = 'receta'.
--     ingredientes_sin_costo cuenta los ingredientes con costo 0 (nunca comprados por
--     factura): el costo queda incompleto y la pantalla lo avisa (H4.4 T04).
--   - sin receta y con productos.precio_compra > 0 (último costo real por unidad de la
--     factura, 0006): origen = 'compra'.
--   - sin ninguno de los dos: origen = 'sin_costo' y costo_unitario NULL; la pantalla muestra
--     el producto sin margen en vez de suponer costo 0.
-- Se devuelven todos los productos (también inactivos: pudieron venderse en el período).
-- La pantalla multiplica el costo por las unidades vendidas y lo resta del monto cobrado
-- (fn_reporte_productos_sucursal, ya con descuentos y venta a empleado).
--
-- Solo lectura (STABLE). SECURITY DEFINER, ejecutable solo por el administrador.
--
-- ANTES DE APLICAR EN PRODUCCIÓN: correr 20261106_costo_actual_productos.ENSAYO.sql (termina
-- en ROLLBACK) y la prueba database/tests/costo_actual_productos.sql.

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_costo_actual_productos()
RETURNS TABLE (
    producto_id            INTEGER,
    origen                 VARCHAR,
    costo_unitario         NUMERIC,
    ingredientes           INTEGER,
    ingredientes_sin_costo INTEGER
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $function$
    WITH receta AS (
        SELECT r.producto_id AS r_producto,
               sum(r.cantidad_necesaria * i.costo_unitario_promedio) AS r_costo,
               count(*)::int AS r_ingredientes,
               count(*) FILTER (WHERE i.costo_unitario_promedio <= 0)::int AS r_sin_costo
          FROM public.recetas r
          JOIN public.ingredientes i ON i.id = r.ingrediente_id
         GROUP BY r.producto_id
    )
    SELECT p.id,
           CASE WHEN rc.r_producto IS NOT NULL THEN 'receta'
                WHEN p.precio_compra > 0 THEN 'compra'
                ELSE 'sin_costo' END::varchar,
           CASE WHEN rc.r_producto IS NOT NULL THEN round(rc.r_costo, 2)
                WHEN p.precio_compra > 0 THEN p.precio_compra
                ELSE NULL END,
           COALESCE(rc.r_ingredientes, 0),
           COALESCE(rc.r_sin_costo, 0)
      FROM public.productos p
      LEFT JOIN receta rc ON rc.r_producto = p.id
     ORDER BY p.id;
$function$;

COMMENT ON FUNCTION public.fn_costo_actual_productos() IS
    'H4.4 T03: costo actual por producto (receta vigente × costo promedio de los ingredientes, o último precio de compra si no tiene receta) para el margen del reporte; sin_costo = sin datos.';

REVOKE ALL ON FUNCTION public.fn_costo_actual_productos() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_costo_actual_productos() TO nury_admin;

COMMIT;

NOTIFY pgrst, 'reload schema';


-- #####################################################################
-- 61. database/migrations/20261106_reporte_cajeros_turno.sql
-- #####################################################################

-- H4.3 T03 - Acotar el reporte de cajeros a un turno real.
--
-- El administrador puede ver el desempeño de un turno concreto (tabla turnos: apertura y
-- cierre reales de la caja), no solo de un rango de días.
--
--   - fn_turnos_reporte(p_sucursales, p_desde, p_hasta): los turnos que empezaron en el
--     período o que tienen ventas en él, con cajero, sucursal, inicio y fin en hora de Chile
--     (fin NULL = turno abierto) y sus ventas válidas, total y anuladas del turno completo.
--     Una última fila con turno_id NULL ("Sin turno registrado") junta las ventas del
--     período sin turno (ventas anteriores a 0003_apertura_control_turno o cargadas aparte).
--   - fn_reporte_cajeros gana p_turno INTEGER DEFAULT NULL:
--       NULL = como antes (período y sucursales);
--       > 0  = solo las ventas de ese turno, aunque crucen la medianoche (el período y las
--              sucursales no se aplican: el turno ya los define);
--       0    = solo las ventas del período sin turno registrado.
--     Sin p_turno responde igual que antes, así que las llamadas existentes (pantalla de
--     Reportes y asistente del Dashboard) no cambian.
--
-- Se cambia la firma de fn_reporte_cajeros: se elimina la de tres parámetros y se crea la de
-- cuatro con el último opcional. Ambas funciones: STABLE, SECURITY DEFINER, solo admin.
--
-- ANTES DE APLICAR EN PRODUCCIÓN: correr 20261106_reporte_cajeros_turno.ENSAYO.sql (termina
-- en ROLLBACK) y la prueba database/tests/reporte_cajeros_turno.sql.

BEGIN;

DROP FUNCTION IF EXISTS public.fn_reporte_cajeros(integer[], date, date);

CREATE OR REPLACE FUNCTION public.fn_reporte_cajeros(
    p_sucursales INTEGER[],
    p_desde      DATE,
    p_hasta      DATE,
    p_turno      INTEGER DEFAULT NULL
)
RETURNS TABLE (
    cajero_id      INTEGER,
    cajero         VARCHAR,
    sucursales     VARCHAR,
    turnos         INTEGER,
    ventas         INTEGER,
    total          NUMERIC,
    venta_promedio NUMERIC,
    productos      NUMERIC,
    anuladas       INTEGER,
    total_anuladas NUMERIC
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $function$
DECLARE
    v_desde TIMESTAMP;
    v_hasta TIMESTAMP;
BEGIN
    IF p_desde IS NULL OR p_hasta IS NULL THEN
        RAISE EXCEPTION 'Indica la fecha inicial y la final del período' USING ERRCODE = '22023';
    END IF;
    IF p_desde > p_hasta THEN
        RAISE EXCEPTION 'La fecha inicial no puede ser posterior a la final' USING ERRCODE = '22023';
    END IF;
    IF p_hasta - p_desde > 366 THEN
        RAISE EXCEPTION 'El período no puede superar un año' USING ERRCODE = '22023';
    END IF;

    IF p_turno < 0 THEN
        RAISE EXCEPTION 'El turno indicado no es válido' USING ERRCODE = '22023';
    END IF;

    v_desde := (p_desde::timestamp AT TIME ZONE 'America/Santiago') AT TIME ZONE current_setting('TimeZone');
    v_hasta := ((p_hasta + 1)::timestamp AT TIME ZONE 'America/Santiago') AT TIME ZONE current_setting('TimeZone');

    RETURN QUERY
    WITH del_periodo AS (
        SELECT v.id AS v_id, v.cajero_id AS v_cajero, v.sucursal_id AS v_sucursal,
               v.turno_id AS v_turno, v.total AS v_total, v.anulada AS v_anulada
          FROM public.ventas v
         WHERE CASE
                   -- Un turno concreto: todas sus ventas, aunque crucen la medianoche; el
                   -- turno ya define la sucursal y el cajero.
                   WHEN p_turno > 0 THEN v.turno_id = p_turno
                   ELSE v.fecha_venta >= v_desde
                    AND v.fecha_venta <  v_hasta
                    AND (p_sucursales IS NULL OR v.sucursal_id = ANY (p_sucursales) OR v.sucursal_id IS NULL)
                    -- 0 = solo las ventas sin turno registrado.
                    AND (p_turno IS NULL OR v.turno_id IS NULL)
               END
    ), unidades AS (
        SELECT d.venta_id AS u_venta, sum(d.cantidad) AS u_cantidad
          FROM public.detalle_venta d
         WHERE d.venta_id IN (SELECT dp.v_id FROM del_periodo dp WHERE NOT dp.v_anulada)
         GROUP BY d.venta_id
    )
    SELECT dp.v_cajero,
           COALESCE(u.nombre, 'Sin cajero')::varchar,
           COALESCE(string_agg(DISTINCT s.nombre, ', '), 'Sin sucursal')::varchar,
           count(DISTINCT dp.v_turno)::int,
           count(*) FILTER (WHERE NOT dp.v_anulada)::int,
           COALESCE(sum(dp.v_total) FILTER (WHERE NOT dp.v_anulada), 0),
           CASE WHEN count(*) FILTER (WHERE NOT dp.v_anulada) = 0 THEN 0
                ELSE round(sum(dp.v_total) FILTER (WHERE NOT dp.v_anulada)
                           / count(*) FILTER (WHERE NOT dp.v_anulada), 2) END,
           COALESCE(sum(un.u_cantidad), 0),
           count(*) FILTER (WHERE dp.v_anulada)::int,
           COALESCE(sum(dp.v_total) FILTER (WHERE dp.v_anulada), 0)
      FROM del_periodo dp
      LEFT JOIN public.usuarios u   ON u.id = dp.v_cajero
      LEFT JOIN public.sucursales s ON s.id = dp.v_sucursal
      LEFT JOIN unidades un         ON un.u_venta = dp.v_id
     GROUP BY dp.v_cajero, u.nombre
     ORDER BY dp.v_cajero IS NULL, COALESCE(sum(dp.v_total) FILTER (WHERE NOT dp.v_anulada), 0) DESC, u.nombre;
END;
$function$;

COMMENT ON FUNCTION public.fn_reporte_cajeros(integer[], date, date, integer) IS
    'H4.3: por cajero, total vendido, ventas, venta promedio y productos vendidos sin anuladas (que van aparte), en un período de días en hora de Chile o en un turno (p_turno > 0; 0 = ventas sin turno).';

REVOKE ALL ON FUNCTION public.fn_reporte_cajeros(integer[], date, date, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_reporte_cajeros(integer[], date, date, integer) TO nury_admin;

CREATE OR REPLACE FUNCTION public.fn_turnos_reporte(
    p_sucursales INTEGER[],
    p_desde      DATE,
    p_hasta      DATE
)
RETURNS TABLE (
    turno_id    INTEGER,
    cajero_id   INTEGER,
    cajero      VARCHAR,
    sucursal_id INTEGER,
    sucursal    VARCHAR,
    inicio      TIMESTAMP,
    fin         TIMESTAMP,
    ventas      INTEGER,
    total       NUMERIC,
    anuladas    INTEGER
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $function$
DECLARE
    v_desde TIMESTAMP;
    v_hasta TIMESTAMP;
BEGIN
    IF p_desde IS NULL OR p_hasta IS NULL THEN
        RAISE EXCEPTION 'Indica la fecha inicial y la final del período' USING ERRCODE = '22023';
    END IF;
    IF p_desde > p_hasta THEN
        RAISE EXCEPTION 'La fecha inicial no puede ser posterior a la final' USING ERRCODE = '22023';
    END IF;
    IF p_hasta - p_desde > 366 THEN
        RAISE EXCEPTION 'El período no puede superar un año' USING ERRCODE = '22023';
    END IF;

    v_desde := (p_desde::timestamp AT TIME ZONE 'America/Santiago') AT TIME ZONE current_setting('TimeZone');
    v_hasta := ((p_hasta + 1)::timestamp AT TIME ZONE 'America/Santiago') AT TIME ZONE current_setting('TimeZone');

    RETURN QUERY
    WITH del_periodo AS (
        -- Turnos que empezaron en el período o que tienen ventas en él.
        SELECT t.id AS t_id
          FROM public.turnos t
         WHERE (p_sucursales IS NULL OR t.sucursal_id = ANY (p_sucursales))
           AND (   (t.hora_inicio >= v_desde AND t.hora_inicio < v_hasta)
                OR EXISTS (SELECT 1 FROM public.ventas v
                            WHERE v.turno_id = t.id
                              AND v.fecha_venta >= v_desde AND v.fecha_venta < v_hasta))
    ), por_turno AS (
        -- Las cifras son del turno completo: lo mismo que muestra fn_reporte_cajeros al elegirlo.
        SELECT t.id AS r_turno, t.usuario_id AS r_cajero, u.nombre::varchar AS r_nombre,
               t.sucursal_id AS r_sucursal, s.nombre::varchar AS r_sucursal_nombre,
               ((t.hora_inicio AT TIME ZONE current_setting('TimeZone')) AT TIME ZONE 'America/Santiago') AS r_inicio,
               ((t.hora_fin AT TIME ZONE current_setting('TimeZone')) AT TIME ZONE 'America/Santiago') AS r_fin,
               count(v.id) FILTER (WHERE NOT v.anulada)::int AS r_ventas,
               COALESCE(sum(v.total) FILTER (WHERE NOT v.anulada), 0) AS r_total,
               count(v.id) FILTER (WHERE v.anulada)::int AS r_anuladas
          FROM del_periodo dp
          JOIN public.turnos t          ON t.id = dp.t_id
          LEFT JOIN public.usuarios u   ON u.id = t.usuario_id
          LEFT JOIN public.sucursales s ON s.id = t.sucursal_id
          LEFT JOIN public.ventas v     ON v.turno_id = t.id
         GROUP BY t.id, u.nombre, s.nombre
    ), sin_turno AS (
        -- Una fila (turno_id NULL) con las ventas del período que no quedaron en ningún turno.
        SELECT count(*) FILTER (WHERE NOT v.anulada)::int AS n_ventas,
               COALESCE(sum(v.total) FILTER (WHERE NOT v.anulada), 0) AS n_total,
               count(*) FILTER (WHERE v.anulada)::int AS n_anuladas
          FROM public.ventas v
         WHERE v.turno_id IS NULL
           AND v.fecha_venta >= v_desde AND v.fecha_venta < v_hasta
           AND (p_sucursales IS NULL OR v.sucursal_id = ANY (p_sucursales) OR v.sucursal_id IS NULL)
    )
    SELECT x.* FROM (
        SELECT pt.r_turno, pt.r_cajero, pt.r_nombre, pt.r_sucursal, pt.r_sucursal_nombre,
               pt.r_inicio, pt.r_fin, pt.r_ventas, pt.r_total, pt.r_anuladas
          FROM por_turno pt
        UNION ALL
        SELECT NULL::int, NULL::int, 'Sin turno registrado'::varchar, NULL::int, NULL::varchar,
               NULL::timestamp, NULL::timestamp, st.n_ventas, st.n_total, st.n_anuladas
          FROM sin_turno st
         WHERE st.n_ventas + st.n_anuladas > 0
    ) x
    ORDER BY x.r_turno IS NULL, x.r_inicio DESC, x.r_turno DESC;
END;
$function$;

COMMENT ON FUNCTION public.fn_turnos_reporte(integer[], date, date) IS
    'H4.3 T03: turnos del período (empezados en él o con ventas en él) con cajero, sucursal, inicio y fin en hora de Chile y sus cifras; fila final turno_id NULL = ventas sin turno.';

REVOKE ALL ON FUNCTION public.fn_turnos_reporte(integer[], date, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_turnos_reporte(integer[], date, date) TO nury_admin;

COMMIT;

NOTIFY pgrst, 'reload schema';


-- #####################################################################
-- 62. database/migrations/20261108_promociones_sucursales.sql
-- #####################################################################

-- H5.2 — Una promoción puede regir en varias sucursales (checklist en Gestión de negocio).
--
-- Antes: promociones.sucursal_id (una sucursal, o NULL = todas). Ahora:
--   promocion_sucursales (promocion_id, sucursal_id)
--     Sucursales donde rige la promoción. Sin filas = todas las sucursales, también las que
--     se abran después. Con filas = solo esas.
-- Se copian las sucursales existentes y se elimina promociones.sucursal_id, para que haya una
-- sola fuente de verdad.
--
-- fn_promocion_en_sucursal(promocion, sucursal): ¿rige la promoción en esa sucursal?
--   SECURITY DEFINER para que la política del cajero sobre `promociones` pueda leer
--   promocion_sucursales sin pasar por la RLS de esa tabla (evita la recursión entre
--   políticas). La usan la política del cajero y fn_promociones_vigentes.
--
-- Se reemplazan:
--   - fn_promociones_vigentes (20261105_promociones_vigentes.sql): misma firma.
--   - política promociones_cajero_vigentes (20261105_promociones_permisos.sql).
--   - fn_guardar_promocion (20261105_guardar_promocion.sql): p_sucursal_id INTEGER pasa a
--     p_sucursales INTEGER[] (NULL o vacío = todas). Cambia la firma: se borra la anterior.
-- fn_registrar_venta usa fn_promociones_vigentes, así que respeta la regla nueva sin cambios.
--
-- Permisos de promocion_sucursales: admin todo; cajero solo lee las filas de su sucursal de
-- promociones que puede ver; bodeguero y web_anon nada.
--
-- Requiere las migraciones de H5.2 del 20261105 (promociones, permisos, vigentes y
-- guardar_promocion). Se puede volver a correr.
-- Prueba: database/tests/promociones_sucursales.sql (y las demás de H5.2, ya actualizadas).

BEGIN;

-- 1) Tabla de sucursales por promoción ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.promocion_sucursales (
    promocion_id INTEGER NOT NULL REFERENCES public.promociones(id) ON DELETE CASCADE,
    sucursal_id  INTEGER NOT NULL REFERENCES public.sucursales(id),
    PRIMARY KEY (promocion_id, sucursal_id)
);

COMMENT ON TABLE public.promocion_sucursales IS
    'Sucursales donde rige cada promoción (H5.2). Sin filas = todas las sucursales.';

CREATE INDEX IF NOT EXISTS idx_promocion_sucursales_sucursal
    ON public.promocion_sucursales(sucursal_id);

-- 2) Datos existentes y columna vieja (solo la primera vez) -------------------------------------
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema = 'public' AND table_name = 'promociones'
                  AND column_name = 'sucursal_id') THEN
        EXECUTE $q$
            INSERT INTO public.promocion_sucursales (promocion_id, sucursal_id)
            SELECT id, sucursal_id FROM public.promociones WHERE sucursal_id IS NOT NULL
            ON CONFLICT DO NOTHING
        $q$;
        -- La política del cajero usa la columna: se borra antes y se vuelve a crear abajo.
        DROP POLICY IF EXISTS promociones_cajero_vigentes ON public.promociones;
        -- Arrastra idx_promociones_sucursal_vigencia.
        ALTER TABLE public.promociones DROP COLUMN sucursal_id;
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_promociones_vigencia ON public.promociones(inicio, termino);

-- 3) ¿Rige la promoción en la sucursal? ----------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_promocion_en_sucursal(
    p_promocion_id INTEGER,
    p_sucursal_id  INTEGER
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT NOT EXISTS (SELECT 1 FROM public.promocion_sucursales
                        WHERE promocion_id = p_promocion_id)
        OR EXISTS (SELECT 1 FROM public.promocion_sucursales
                    WHERE promocion_id = p_promocion_id AND sucursal_id = p_sucursal_id);
$$;

COMMENT ON FUNCTION public.fn_promocion_en_sucursal(INTEGER, INTEGER) IS
    'TRUE si la promoción rige en la sucursal: no tiene sucursales (todas) o la incluye (H5.2).';

REVOKE ALL ON FUNCTION public.fn_promocion_en_sucursal(INTEGER, INTEGER) FROM PUBLIC, web_anon, nury_bodeguero;
GRANT EXECUTE ON FUNCTION public.fn_promocion_en_sucursal(INTEGER, INTEGER) TO nury_admin, nury_cajero;

-- 4) Promociones vigentes (misma firma) -------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_promociones_vigentes(
    p_sucursal_id INTEGER,
    p_momento     TIMESTAMPTZ DEFAULT now()
)
RETURNS SETOF public.promociones
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
    SELECT p.*
      FROM public.promociones p
     WHERE p.activa
       AND p.inicio <= p_momento
       AND p_momento < p.termino
       AND public.fn_promocion_en_sucursal(p.id, p_sucursal_id)
     ORDER BY p.prioridad DESC, p.id;
$$;

COMMENT ON FUNCTION public.fn_promociones_vigentes(INTEGER, TIMESTAMPTZ) IS
    'Promociones que se aplican en ese momento (por defecto ahora, hora del servidor) en la sucursal: activas, inicio <= momento < termino, de esa sucursal o de todas (H5.2).';

REVOKE ALL ON FUNCTION public.fn_promociones_vigentes(INTEGER, TIMESTAMPTZ) FROM PUBLIC, web_anon, nury_bodeguero;
GRANT EXECUTE ON FUNCTION public.fn_promociones_vigentes(INTEGER, TIMESTAMPTZ) TO nury_admin, nury_cajero;

-- 5) Permisos y RLS -----------------------------------------------------------------------------------
DROP POLICY IF EXISTS promociones_cajero_vigentes ON public.promociones;
CREATE POLICY promociones_cajero_vigentes ON public.promociones FOR SELECT TO nury_cajero
    USING (
        activa
        AND inicio <= now() AND now() < termino
        AND public.fn_promocion_en_sucursal(id, (SELECT public.fn_sucursal_actual_id()))
    );

REVOKE ALL ON public.promocion_sucursales FROM PUBLIC, web_anon, nury_bodeguero, nury_cajero;
GRANT SELECT ON public.promocion_sucursales TO nury_cajero;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.promocion_sucursales TO nury_admin;

ALTER TABLE public.promocion_sucursales ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS promocion_sucursales_admin ON public.promocion_sucursales;
CREATE POLICY promocion_sucursales_admin ON public.promocion_sucursales TO nury_admin
    USING (TRUE) WITH CHECK (TRUE);

-- La subconsulta pasa por la política de promociones: solo las que el cajero puede aplicar.
DROP POLICY IF EXISTS promocion_sucursales_cajero ON public.promocion_sucursales;
CREATE POLICY promocion_sucursales_cajero ON public.promocion_sucursales FOR SELECT TO nury_cajero
    USING (
        sucursal_id = (SELECT public.fn_sucursal_actual_id())
        AND EXISTS (SELECT 1 FROM public.promociones p WHERE p.id = promocion_id)
    );

-- 6) Guardar promoción con varias sucursales ------------------------------------------------------
DROP FUNCTION IF EXISTS public.fn_guardar_promocion(INTEGER, TEXT, TEXT, NUMERIC, INTEGER, TIMESTAMPTZ, TIMESTAMPTZ, JSONB);

CREATE OR REPLACE FUNCTION public.fn_guardar_promocion(
    p_id          INTEGER,
    p_nombre      TEXT,
    p_tipo        TEXT,
    p_valor       NUMERIC,
    p_sucursales  INTEGER[],
    p_inicio      TIMESTAMPTZ,
    p_termino     TIMESTAMPTZ,
    p_productos   JSONB
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, pg_temp
AS $function$
DECLARE
    v_id     INTEGER;
    v_nombre TEXT := btrim(COALESCE(p_nombre, ''));
    v_lineas INTEGER;
    v_texto  TEXT;
BEGIN
    IF v_nombre = '' OR length(v_nombre) > 120 THEN
        RAISE EXCEPTION 'Ingresa un nombre de hasta 120 caracteres.' USING ERRCODE = '22023';
    END IF;
    IF p_tipo IS NULL OR p_tipo NOT IN ('porcentaje', 'monto_fijo') THEN
        RAISE EXCEPTION 'El tipo de descuento debe ser porcentaje o monto fijo.' USING ERRCODE = '22023';
    END IF;
    IF p_valor IS NULL OR p_valor <= 0 THEN
        RAISE EXCEPTION 'El descuento debe ser mayor que 0.' USING ERRCODE = '22023';
    END IF;
    IF p_tipo = 'porcentaje' AND p_valor > 100 THEN
        RAISE EXCEPTION 'El porcentaje no puede ser mayor a 100.' USING ERRCODE = '22023';
    END IF;
    IF p_inicio IS NULL OR p_termino IS NULL THEN
        RAISE EXCEPTION 'Indica la fecha y hora de inicio y de término.' USING ERRCODE = '22023';
    END IF;
    IF p_termino <= p_inicio THEN
        RAISE EXCEPTION 'El término debe ser posterior al inicio.' USING ERRCODE = '22023';
    END IF;

    -- Sucursales: NULL o vacío = todas. Las elegidas deben existir y estar activas.
    SELECT string_agg(COALESCE(s.nombre, '#' || COALESCE(x.id::text, 'vacía')), ', ' ORDER BY x.id)
      INTO v_texto
      FROM (SELECT DISTINCT unnest(COALESCE(p_sucursales, '{}')) AS id) x
      LEFT JOIN public.sucursales s ON s.id = x.id
     WHERE x.id IS NULL OR s.id IS NULL OR NOT s.activo;
    IF v_texto IS NOT NULL THEN
        RAISE EXCEPTION 'Estas sucursales no existen o están inactivas: %.', v_texto
            USING ERRCODE = '22023';
    END IF;

    -- Productos: arreglo no vacío de {producto_id, cantidad > 0}, sin repetir.
    IF p_productos IS NULL OR jsonb_typeof(p_productos) <> 'array'
       OR jsonb_array_length(p_productos) = 0 THEN
        RAISE EXCEPTION 'Agrega al menos un producto.' USING ERRCODE = '22023';
    END IF;
    IF EXISTS (
        SELECT 1 FROM jsonb_array_elements(p_productos) e
         WHERE jsonb_typeof(e) <> 'object'
            OR jsonb_typeof(e -> 'producto_id') IS DISTINCT FROM 'number'
            OR jsonb_typeof(e -> 'cantidad') IS DISTINCT FROM 'number'
            OR (e ->> 'cantidad')::numeric <= 0
            OR (e ->> 'cantidad')::numeric <> trunc((e ->> 'cantidad')::numeric)
    ) THEN
        RAISE EXCEPTION 'Cada producto necesita una cantidad entera mayor que 0.' USING ERRCODE = '22023';
    END IF;

    SELECT count(*) INTO v_lineas FROM jsonb_array_elements(p_productos);
    IF v_lineas <> (SELECT count(DISTINCT (e ->> 'producto_id')::integer)
                      FROM jsonb_array_elements(p_productos) e) THEN
        RAISE EXCEPTION 'Un producto aparece más de una vez: ajusta su cantidad.' USING ERRCODE = '22023';
    END IF;

    SELECT string_agg(COALESCE(p.nombre, '#' || l.producto_id), ', ' ORDER BY l.producto_id)
      INTO v_texto
      FROM (SELECT (e ->> 'producto_id')::integer AS producto_id
              FROM jsonb_array_elements(p_productos) e) l
      LEFT JOIN public.productos p ON p.id = l.producto_id
     WHERE p.id IS NULL OR NOT p.activo;
    IF v_texto IS NOT NULL THEN
        RAISE EXCEPTION 'Estos productos no existen o están inactivos: %.', v_texto
            USING ERRCODE = '22023';
    END IF;

    -- Promoción -----------------------------------------------------------------------------
    IF p_id IS NULL THEN
        INSERT INTO public.promociones
            (nombre, tipo, valor_descuento, inicio, termino, creado_por)
        VALUES
            (v_nombre, p_tipo, p_valor, p_inicio, p_termino, public.fn_usuario_actual_id())
        RETURNING id INTO v_id;
    ELSE
        UPDATE public.promociones
           SET nombre          = v_nombre,
               tipo            = p_tipo,
               valor_descuento = p_valor,
               inicio          = p_inicio,
               termino         = p_termino
         WHERE id = p_id
        RETURNING id INTO v_id;
        IF v_id IS NULL THEN
            RAISE EXCEPTION 'La promoción #% no existe.', p_id USING ERRCODE = 'P0002';
        END IF;
        DELETE FROM public.promocion_productos WHERE promocion_id = v_id;
        DELETE FROM public.promocion_sucursales WHERE promocion_id = v_id;
    END IF;

    INSERT INTO public.promocion_productos (promocion_id, producto_id, cantidad)
        SELECT v_id, (e ->> 'producto_id')::integer, (e ->> 'cantidad')::integer
          FROM jsonb_array_elements(p_productos) e;

    INSERT INTO public.promocion_sucursales (promocion_id, sucursal_id)
        SELECT DISTINCT v_id, unnest(COALESCE(p_sucursales, '{}'));

    RETURN v_id;
END;
$function$;

COMMENT ON FUNCTION public.fn_guardar_promocion(INTEGER, TEXT, TEXT, NUMERIC, INTEGER[], TIMESTAMPTZ, TIMESTAMPTZ, JSONB) IS
    'Crea (p_id NULL) o edita una promoción con sus productos y sucursales (vacío = todas) en una sola transacción (H5.2).';

REVOKE ALL ON FUNCTION public.fn_guardar_promocion(INTEGER, TEXT, TEXT, NUMERIC, INTEGER[], TIMESTAMPTZ, TIMESTAMPTZ, JSONB)
    FROM PUBLIC, web_anon, nury_cajero, nury_bodeguero;
GRANT EXECUTE ON FUNCTION public.fn_guardar_promocion(INTEGER, TEXT, TEXT, NUMERIC, INTEGER[], TIMESTAMPTZ, TIMESTAMPTZ, JSONB)
    TO nury_admin;

COMMIT;

NOTIFY pgrst, 'reload schema';
