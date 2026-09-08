-- =====================================================================
-- HygieTrack — Base de datos local (v2, consolidada)
-- Motor: PostgreSQL 15.x
-- Alcance: Módulo 1 — Gestión de órdenes de servicio (captura vía RPA)
--
-- Reemplaza por completo a hygietrack_bd_local_v1.sql y a las
-- migraciones 002 y 003. Ejecutar sobre una base vacía:
--
--     DROP SCHEMA public CASCADE;
--     CREATE SCHEMA public;
--     GRANT ALL ON SCHEMA public TO hygietrack_app;
--
-- Luego, conectado como hygietrack_app:  \i 'ruta/al/archivo.sql'
-- =====================================================================


SET client_encoding TO 'UTF8';

-- ---------------------------------------------------------------------
-- 0. Utilidades
-- ---------------------------------------------------------------------

-- Quita tildes sin depender de la extensión unaccent (que no siempre
-- está disponible en RDS con usuarios sin superusuario).
-- Las vocales acentuadas van como escapes Unicode para que el script
-- se pueda ejecutar desde cualquier consola, sin importar su codepage.
CREATE OR REPLACE FUNCTION fn_normalizar(p_texto text)
RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT lower(translate(coalesce(p_texto, ''),
        E'\u00E1\u00E9\u00ED\u00F3\u00FA\u00FC\u00F1\u00C1\u00C9\u00CD\u00D3\u00DA\u00DC\u00D1',
        'aeiouunAEIOUUN'));
$$;

-- Convierte 'DD/MM/YYYY' (con o sin apóstrofe inicial) a date.
-- Devuelve NULL si el texto no es una fecha válida, en vez de fallar.
CREATE OR REPLACE FUNCTION fn_texto_a_fecha(p_texto text)
RETURNS date
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
    v_limpio text;
BEGIN
    v_limpio := regexp_replace(coalesce(p_texto, ''), '[^0-9/]', '', 'g');
    IF v_limpio = '' THEN
        RETURN NULL;
    END IF;
    RETURN to_date(v_limpio, 'DD/MM/YYYY');
EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
END;
$$;

-- Convierte '$ 1.234.567,89' o '1234567' a numeric.
CREATE OR REPLACE FUNCTION fn_texto_a_numero(p_texto text)
RETURNS numeric
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
    v_limpio text;
BEGIN
    v_limpio := regexp_replace(coalesce(p_texto, ''), '[^0-9,\.]', '', 'g');
    v_limpio := replace(v_limpio, '.', '');
    v_limpio := replace(v_limpio, ',', '.');
    IF v_limpio = '' THEN
        RETURN NULL;
    END IF;
    RETURN v_limpio::numeric;
EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
END;
$$;

-- ---------------------------------------------------------------------
-- 1. Catálogos
-- ---------------------------------------------------------------------

CREATE TABLE arl (
    id              smallserial PRIMARY KEY,
    codigo          varchar(20)  NOT NULL UNIQUE,   -- COLMENA, SURA
    nombre          varchar(120) NOT NULL,
    activo          boolean      NOT NULL DEFAULT true
);

CREATE TABLE empresa_cliente (
    id              serial PRIMARY KEY,
    nit             varchar(20)  NOT NULL UNIQUE,
    razon_social    varchar(200) NOT NULL,
    creado_en       timestamptz  NOT NULL DEFAULT now()
);

CREATE TABLE contrato (
    id                  serial PRIMARY KEY,
    arl_id              smallint     NOT NULL REFERENCES arl(id),
    empresa_cliente_id  integer      NOT NULL REFERENCES empresa_cliente(id),
    numero_contrato     varchar(40)  NOT NULL,
    creado_en           timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT uq_contrato_arl UNIQUE (arl_id, numero_contrato)
);

CREATE TABLE ciudad (
    id                  serial PRIMARY KEY,
    nombre              varchar(120) NOT NULL UNIQUE,
    -- Regla de negocio: toda ciudad distinta de Bogotá genera viáticos.
    -- Es un atributo de la ciudad, no un texto repetido en cada orden.
    genera_viaticos     boolean      NOT NULL DEFAULT true
);

CREATE TABLE actividad (
    id              serial PRIMARY KEY,
    nombre          varchar(250) NOT NULL UNIQUE
);

CREATE TABLE responsable_arl (
    id              serial PRIMARY KEY,
    arl_id          smallint     NOT NULL REFERENCES arl(id),
    nombre          varchar(200) NOT NULL,
    correo          varchar(200),
    CONSTRAINT uq_responsable_arl UNIQUE (arl_id, nombre)
);

-- Higienistas y especialistas de HISO que ejecutan las órdenes.
-- Corresponde a la columna N del archivo "ORDENES COLMENA".
CREATE TABLE profesional_hiso (
    id              serial PRIMARY KEY,
    documento       varchar(20)  UNIQUE,
    nombre          varchar(200) NOT NULL UNIQUE,
    correo          varchar(200),
    telefono        varchar(30),
    activo          boolean      NOT NULL DEFAULT true,
    creado_en       timestamptz  NOT NULL DEFAULT now()
);

-- Estados tal como los nombra HISO en su operación diaria.
-- 'codigo' es el identificador estable que usa el software;
-- 'nombre' es lo que ve el usuario en pantalla.
CREATE TABLE estado_orden (
    id              smallserial PRIMARY KEY,
    codigo          varchar(30)  NOT NULL UNIQUE,
    nombre          varchar(60)  NOT NULL,
    orden_flujo     smallint     NOT NULL,
    es_inicial      boolean      NOT NULL DEFAULT false,
    es_final        boolean      NOT NULL DEFAULT false
);

-- Solo puede haber un estado inicial (el que asigna el RPA al capturar).
CREATE UNIQUE INDEX uq_estado_inicial
    ON estado_orden (es_inicial) WHERE es_inicial = true;

-- ---------------------------------------------------------------------
-- 2. Orden de servicio
-- ---------------------------------------------------------------------

CREATE TABLE orden_servicio (
    id                      bigserial PRIMARY KEY,
    arl_id                  smallint     NOT NULL REFERENCES arl(id),
    numero_orden            varchar(30)  NOT NULL,

    -- Código que usa el portal en la URL del formato de prestación.
    -- Se deriva del número de orden, no se captura aparte.
    codigo_portal           varchar(30)
        GENERATED ALWAYS AS (substring(numero_orden from 4)) STORED,

    contrato_id             integer      REFERENCES contrato(id),
    responsable_arl_id      integer      REFERENCES responsable_arl(id),
    actividad_id            integer      NOT NULL REFERENCES actividad(id),
    ciudad_id               integer      NOT NULL REFERENCES ciudad(id),
    estado_id               smallint     NOT NULL REFERENCES estado_orden(id),

    -- La asigna el coordinador; el RPA la deja vacía.
    profesional_hiso_id     integer      REFERENCES profesional_hiso(id),

    cantidad_solicitada     integer      CHECK (cantidad_solicitada > 0),
    lugar_realizacion       text,
    contacto_actividad      text,
    fecha_publicacion       date,
    fecha_inicio            date,
    fecha_fin               date,
    observaciones           text,
    valor_total             numeric(14,2) CHECK (valor_total >= 0),

    origen_captura          varchar(10)  NOT NULL DEFAULT 'RPA'
        CHECK (origen_captura IN ('RPA', 'MANUAL')),
    fecha_captura           timestamptz  NOT NULL DEFAULT now(),
    actualizado_en          timestamptz  NOT NULL DEFAULT now(),

    CONSTRAINT uq_orden_arl UNIQUE (arl_id, numero_orden),
    CONSTRAINT ck_orden_fechas CHECK (fecha_fin IS NULL
                                      OR fecha_inicio IS NULL
                                      OR fecha_fin >= fecha_inicio)
);

CREATE INDEX ix_orden_fecha_captura ON orden_servicio (fecha_captura DESC);
CREATE INDEX ix_orden_fecha_pub     ON orden_servicio (fecha_publicacion);
CREATE INDEX ix_orden_estado        ON orden_servicio (estado_id);
CREATE INDEX ix_orden_ciudad        ON orden_servicio (ciudad_id);

-- Soporta la validación de disponibilidad del módulo 2:
-- qué tiene asignado un profesional en un rango de fechas.
CREATE INDEX ix_orden_agenda
    ON orden_servicio (profesional_hiso_id, fecha_inicio, fecha_fin);

-- Trazabilidad de estados: permite contar reprogramaciones y auditar
-- el recorrido completo de la orden.
CREATE TABLE orden_historial_estado (
    id                  bigserial PRIMARY KEY,
    orden_servicio_id   bigint       NOT NULL REFERENCES orden_servicio(id) ON DELETE CASCADE,
    estado_id           smallint     NOT NULL REFERENCES estado_orden(id),
    fecha_cambio        timestamptz  NOT NULL DEFAULT now(),
    actor               varchar(120) NOT NULL DEFAULT 'RPA',
    nota                text
);

CREATE INDEX ix_historial_orden
    ON orden_historial_estado (orden_servicio_id, fecha_cambio DESC);

-- Formato de prestación de servicios y demás soportes.
CREATE TABLE orden_documento (
    id                  bigserial PRIMARY KEY,
    orden_servicio_id   bigint       NOT NULL REFERENCES orden_servicio(id) ON DELETE CASCADE,
    tipo                varchar(40)  NOT NULL DEFAULT 'FORMATO_PRESTACION',
    nombre_archivo      varchar(255) NOT NULL,
    ruta                text         NOT NULL,   -- ruta local hoy; S3 después
    cargado_en          timestamptz  NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- 3. Capa de integración con el RPA
-- ---------------------------------------------------------------------

-- El robot escribe aquí en crudo, todo como texto, tal como lo entrega
-- el portal. La normalización la hace la base, no Power Automate.
CREATE TABLE rpa_stg_orden (
    id                      bigserial PRIMARY KEY,
    arl_codigo              varchar(20) NOT NULL DEFAULT 'COLMENA',
    num_orden               text,
    responsable_colmena     text,
    num_contrato            text,
    nit_orden               text,
    empresa                 text,
    actividad               text,
    cantidad_solicitada     text,
    lugar_realizacion       text,
    contacto_actividad      text,
    ciudad_desarrollo       text,
    fecha_publicacion       text,
    fecha_inicio            text,
    fecha_fin               text,
    observaciones           text,
    valor_total             text,
    recibido_en             timestamptz NOT NULL DEFAULT now(),
    procesado               boolean     NOT NULL DEFAULT false,
    procesado_en            timestamptz,
    error_mensaje           text
);

CREATE INDEX ix_stg_pendientes ON rpa_stg_orden (procesado) WHERE procesado = false;

-- Bitácora de cada corrida del robot.
CREATE TABLE rpa_ejecucion (
    id                  bigserial PRIMARY KEY,
    arl_id              smallint    NOT NULL REFERENCES arl(id),
    inicio              timestamptz NOT NULL DEFAULT now(),
    fin                 timestamptz,
    ordenes_detectadas  integer     NOT NULL DEFAULT 0,
    ordenes_cargadas    integer     NOT NULL DEFAULT 0,
    resultado           varchar(20) NOT NULL DEFAULT 'EN_CURSO'
        CHECK (resultado IN ('EN_CURSO', 'OK', 'SIN_DATOS', 'ERROR')),
    detalle             text
);

-- ---------------------------------------------------------------------
-- 4. Carga: staging -> modelo normalizado
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION sp_procesar_ordenes_rpa()
RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE
    r               rpa_stg_orden%ROWTYPE;
    v_arl_id        smallint;
    v_empresa_id    integer;
    v_contrato_id   integer;
    v_ciudad_id     integer;
    v_actividad_id  integer;
    v_resp_id       integer;
    v_estado_id     smallint;
    v_orden_id      bigint;
    v_cargadas      integer := 0;
BEGIN
    SELECT id INTO v_estado_id FROM estado_orden WHERE es_inicial = true;
    IF v_estado_id IS NULL THEN
        RAISE EXCEPTION 'No hay un estado inicial definido en estado_orden';
    END IF;

    FOR r IN SELECT * FROM rpa_stg_orden WHERE procesado = false ORDER BY id LOOP
        BEGIN
            SELECT id INTO v_arl_id FROM arl WHERE codigo = upper(r.arl_codigo);
            IF v_arl_id IS NULL THEN
                RAISE EXCEPTION 'ARL desconocida: %', r.arl_codigo;
            END IF;

            INSERT INTO empresa_cliente (nit, razon_social)
            VALUES (nullif(trim(r.nit_orden), ''), upper(trim(r.empresa)))
            ON CONFLICT (nit) DO UPDATE SET razon_social = EXCLUDED.razon_social
            RETURNING id INTO v_empresa_id;

            v_contrato_id := NULL;
            IF nullif(trim(r.num_contrato), '') IS NOT NULL THEN
                INSERT INTO contrato (arl_id, empresa_cliente_id, numero_contrato)
                VALUES (v_arl_id, v_empresa_id, trim(r.num_contrato))
                ON CONFLICT (arl_id, numero_contrato) DO UPDATE
                    SET empresa_cliente_id = EXCLUDED.empresa_cliente_id
                RETURNING id INTO v_contrato_id;
            END IF;

            -- Los viáticos se deciden una sola vez, al dar de alta la ciudad.
            INSERT INTO ciudad (nombre, genera_viaticos)
            VALUES (upper(trim(r.ciudad_desarrollo)),
                    fn_normalizar(r.ciudad_desarrollo) NOT LIKE '%bogota%')
            ON CONFLICT (nombre) DO UPDATE SET nombre = EXCLUDED.nombre
            RETURNING id INTO v_ciudad_id;

            INSERT INTO actividad (nombre)
            VALUES (upper(trim(r.actividad)))
            ON CONFLICT (nombre) DO UPDATE SET nombre = EXCLUDED.nombre
            RETURNING id INTO v_actividad_id;

            v_resp_id := NULL;
            IF nullif(trim(r.responsable_colmena), '') IS NOT NULL THEN
                INSERT INTO responsable_arl (arl_id, nombre)
                VALUES (v_arl_id, upper(trim(r.responsable_colmena)))
                ON CONFLICT (arl_id, nombre) DO UPDATE SET nombre = EXCLUDED.nombre
                RETURNING id INTO v_resp_id;
            END IF;

            INSERT INTO orden_servicio (
                arl_id, numero_orden, contrato_id, responsable_arl_id,
                actividad_id, ciudad_id, estado_id, cantidad_solicitada,
                lugar_realizacion, contacto_actividad, fecha_publicacion,
                fecha_inicio, fecha_fin, observaciones, valor_total, origen_captura
            ) VALUES (
                v_arl_id,
                trim(r.num_orden),
                v_contrato_id,
                v_resp_id,
                v_actividad_id,
                v_ciudad_id,
                v_estado_id,
                nullif(regexp_replace(coalesce(r.cantidad_solicitada, ''), '[^0-9]', '', 'g'), '')::integer,
                nullif(trim(r.lugar_realizacion), ''),
                nullif(trim(r.contacto_actividad), ''),
                fn_texto_a_fecha(r.fecha_publicacion),
                fn_texto_a_fecha(r.fecha_inicio),
                fn_texto_a_fecha(r.fecha_fin),
                nullif(trim(r.observaciones), ''),
                fn_texto_a_numero(r.valor_total),
                'RPA'
            )
            ON CONFLICT (arl_id, numero_orden) DO NOTHING
            RETURNING id INTO v_orden_id;

            IF v_orden_id IS NOT NULL THEN
                INSERT INTO orden_historial_estado (orden_servicio_id, estado_id, actor, nota)
                VALUES (v_orden_id, v_estado_id, 'RPA',
                        'Captura automática desde el portal de la ARL');
                v_cargadas := v_cargadas + 1;
            END IF;

            UPDATE rpa_stg_orden
               SET procesado = true, procesado_en = now(), error_mensaje = NULL
             WHERE id = r.id;

        EXCEPTION WHEN OTHERS THEN
            UPDATE rpa_stg_orden
               SET procesado = false, error_mensaje = SQLERRM
             WHERE id = r.id;
        END;
    END LOOP;

    RETURN v_cargadas;
END;
$$;

-- ---------------------------------------------------------------------
-- 5. Vistas
-- ---------------------------------------------------------------------

-- Reemplaza a comunicacion.json: última orden capturada por ARL.
CREATE OR REPLACE VIEW v_ultima_orden_capturada AS
SELECT DISTINCT ON (o.arl_id)
       a.codigo        AS arl_codigo,
       o.numero_orden,
       o.fecha_captura
  FROM orden_servicio o
  JOIN arl a ON a.id = o.arl_id
 ORDER BY o.arl_id, o.fecha_captura DESC, o.id DESC;

-- Equivalente a las columnas del Excel "ORDENES COLMENA".
CREATE OR REPLACE VIEW v_orden_consolidada AS
SELECT o.id,
       upper(to_char(o.fecha_publicacion, 'TMMonth'))          AS mes,
       o.numero_orden,
       a.codigo                                                AS arl,
       ra.nombre                                               AS responsable_arl,
       c.numero_contrato,
       ec.nit,
       ec.razon_social                                         AS empresa,
       o.cantidad_solicitada || ' ' || act.nombre              AS actividad,
       eo.nombre                                               AS estado,
       o.lugar_realizacion,
       o.contacto_actividad,
       ci.nombre                                               AS ciudad,
       CASE WHEN ci.genera_viaticos THEN 'SI' ELSE 'NO' END    AS viaticos,
       ph.nombre                                               AS profesional_hiso,
       o.fecha_publicacion,
       o.fecha_inicio,
       o.fecha_fin,
       o.fecha_captura::date                                   AS fecha_carga,
       o.observaciones,
       o.valor_total
  FROM orden_servicio o
  JOIN arl a               ON a.id   = o.arl_id
  JOIN actividad act       ON act.id = o.actividad_id
  JOIN ciudad ci           ON ci.id  = o.ciudad_id
  JOIN estado_orden eo     ON eo.id  = o.estado_id
  LEFT JOIN contrato c     ON c.id   = o.contrato_id
  LEFT JOIN empresa_cliente ec  ON ec.id = c.empresa_cliente_id
  LEFT JOIN responsable_arl ra  ON ra.id = o.responsable_arl_id
  LEFT JOIN profesional_hiso ph ON ph.id = o.profesional_hiso_id;

-- ---------------------------------------------------------------------
-- 6. Datos iniciales
-- ---------------------------------------------------------------------

INSERT INTO arl (codigo, nombre) VALUES
    ('COLMENA', 'Colmena Seguros'),
    ('SURA',    'ARL Sura')
ON CONFLICT (codigo) DO NOTHING;

INSERT INTO ciudad (nombre, genera_viaticos) VALUES
    ('BOGOTA',      false),
    ('BOGOTA D.C.', false)
ON CONFLICT (nombre) DO NOTHING;

-- ===== ESTADOS =======================================================
-- Único estado confirmado: el que escribe el RPA al capturar la orden.
-- Los demás salen de los valores reales de la columna I del Excel
-- "ORDENES COLMENA" y se agregan aquí, respetando el orden del flujo.
-- =====================================================================

INSERT INTO estado_orden (codigo, nombre, orden_flujo, es_inicial, es_final) VALUES
    ('PTE_LLAMAR',       'PTE-LLAMAR',             1, true,  false),
    ('PROGRAMADA',       'PROGRAMADA',             2, false, false),
    ('EN_EJECUCION',     'EN EJECUCION',           3, false, false),
    ('REPROGRAMADA',     'REPROGRAMADA',           4, false, false),
    ('EN_ELABORACION',   'EN ELABORACION INFORME', 5, false, false),
    ('EN_REVISION',      'EN REVISION INFORME',    6, false, false),
    ('INFORME_FINAL',    'INFORME FINALIZADO',     7, false, true),
    ('CANCELADA',        'CANCELADA',              8, false, true)
ON CONFLICT (codigo) DO NOTHING;
