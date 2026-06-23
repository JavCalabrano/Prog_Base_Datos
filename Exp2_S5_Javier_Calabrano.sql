
-- Definicion de variables para BIND
VARIABLE v_fecha_proceso VARCHAR(6);
VARIABLE v_limite NUMBER;

-- Ejecutar variables BIND - con variables & antes de la ejecucion
EXEC :v_fecha_proceso := '062026';
EXEC :v_limite := 250000;

DECLARE
    -- VARRAY con los porcentajes de asignacion por movilidad
    TYPE t_asig_movilidad IS VARRAY(5) OF NUMBER;
    v_porcetajes_mov t_asig_movilidad := t_asig_movilidad(2, 4, 5, 7, 9);
    
    -- VARRAY con los porcentajes de asignacion por contrato
    TYPE t_porcetajes_tipo IS VARRAY(4) OF NUMBER;
    v_porcetajes_tipo t_porcetajes_tipo := t_porcetajes_tipo(15, 10, 5, 5);
    
     -- VARRAY con los porcentajes de asignacion por profesion
    TYPE t_porcetajes_prof IS VARRAY(7) OF NUMBER;
    v_porcetajes_prof t_porcetajes_prof := t_porcetajes_prof(12.3, 14.36, 21.34, 14.32, 22.44, 12.36, 18.23);
    
    
    -- Creacion a tipo para obtener datos del profesional
    TYPE t_datos_prof_rec IS RECORD (
        numrun_prof         profesional.numrun_prof%TYPE,
        dvrun_prof          profesional.dvrun_prof%TYPE,
        cod_comuna          profesional.cod_comuna%TYPE,
        cod_profesion       profesional.cod_profesion%TYPE,
        nombre_profesion    profesion.nombre_profesion%TYPE,
        appaterno           profesional.appaterno%TYPE,
        apmaterno           profesional.apmaterno%TYPE,
        nombre              profesional.nombre%TYPE,
        sueldo              profesional.sueldo%TYPE,
        cod_tpcontrato      profesional.cod_tpcontrato%TYPE
    );
    
    -- Asigno tipo a variable para uso de los datos
    v_profesional t_datos_prof_rec;
    
    -- Cursor para obtener los datos que se grabarán en el RECORD
    CURSOR c_profesional IS SELECT 
        p.numrun_prof,
        p.dvrun_prof,
        p.cod_comuna,
        p.cod_profesion,
        prof.nombre_profesion,
        p.appaterno,
        p.apmaterno,
        p.nombre,
        p.sueldo,
        p.cod_tpcontrato
    FROM profesional p
    JOIN profesion prof ON p.cod_profesion = prof.cod_profesion
    ORDER BY prof.nombre_profesion, p.appaterno, p.nombre;
    
-- Declaro variables para hacer los cálculos
    v_mes           NUMBER;
    v_anno          NUMBER;
    v_limite_asig   NUMBER;
    v_count         NUMBER;
    v_sum           NUMBER;
    v_sueldo        NUMBER;
    v_incentivo     NUMBER;
    v_porcentaje    NUMBER;
    v_movil         NUMBER;
    v_asig_tipo     NUMBER;
    v_asig_prof     NUMBER;
    v_total         NUMBER;

-- Declaro mi EXCEPTION por superar el limite de asignacion
    ex_limite_asig EXCEPTION;
    PRAGMA EXCEPTION_INIT (ex_limite_asig, -20010);

BEGIN
    -- Obtengo las variables BIND
    v_mes := TO_NUMBER(SUBSTR(:v_fecha_proceso, 1, 2));
    v_anno := TO_NUMBER(SUBSTR(:v_fecha_proceso, 3, 4));
    v_limite_asig := :v_limite;
    
    -- Trunco las tablas
    EXECUTE IMMEDIATE 'TRUNCATE TABLE detalle_asignacion_mes';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE resumen_mes_profesion';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE errores_proceso';
    
    -- Creo y reinicio la SEQ de los IDs para el registro de errores
    EXECUTE IMMEDIATE 'DROP SEQUENCE sq_error';
    EXECUTE IMMEDIATE 'CREATE SEQUENCE sq_error START WITH 1 INCREMENT BY 1';
    
    -- Loop para obetener datos de los profesionales
    FOR v_profesional IN c_profesional LOOP
        
        BEGIN -- Cantidad y total de honorarios de asesorías del mes/año
        SELECT NVL(COUNT(*), 0), NVL(SUM(honorario), 0)
        INTO v_count, v_sum
        FROM asesoria
        WHERE numrun_prof = v_profesional.numrun_prof
        AND EXTRACT(MONTH FROM inicio_asesoria) = v_mes
        AND EXTRACT(YEAR  FROM inicio_asesoria) = v_anno;
        
        --Divididos por busquedas como si fueran funciones de programación
          BEGIN -- Incentivo por tipo de contrato (si es NULL, se asigna 0)
            SELECT incentivo
              INTO v_incentivo
              FROM tipo_contrato
             WHERE cod_tpcontrato = v_profesional.cod_tpcontrato;
          EXCEPTION
            WHEN NO_DATA_FOUND THEN
              v_incentivo := 0;
          END;
    
          BEGIN  -- Asignación por profesión; si falla, se registra error y se asigna 0
            SELECT asignacion
              INTO v_porcentaje
              FROM porcentaje_profesion
             WHERE cod_profesion = v_profesional.cod_profesion;
          EXCEPTION
            WHEN NO_DATA_FOUND THEN
              v_porcentaje := 0;
              INSERT INTO errores_proceso
                (error_id, mensaje_error_oracle, mensaje_error_usr)
              VALUES
                (sq_error.NEXTVAL,
                 'No se encontró porcentaje para la profesión ' || v_profesional.cod_profesion,
                 'Porcentaje de profesión no definido');
            WHEN OTHERS THEN
              v_porcentaje := 0;
              INSERT INTO errores_proceso
                (error_id, mensaje_error_oracle, mensaje_error_usr)
              VALUES
                (sq_error.NEXTVAL, SQLERRM, 'Error al obtener porcentaje de profesión');
          END;
    
          -- Calcular asignación por movilización extra (9% de los honorarios)
          -- Solo si comuna = 89 (Macul) y el total de honorarios < 680.000
          IF v_prof.cod_comuna = 82 AND v_sum < 350000 THEN
          v_movil := ROUND(v_sum * v_porcetajes_mov(1) / 100);  -- 2%
          ELSIF v_prof.cod_comuna = 83 THEN
          v_movil := ROUND(v_sum * v_porcetajes_mov(2) / 100);  -- 4%
          ELSIF v_prof.cod_comuna = 85 AND v_sum < 400000 THEN
          v_movil := ROUND(v_sum * v_porcetajes_mov(3) / 100);  -- 5%
          ELSIF v_prof.cod_comuna = 86 AND v_sum < 800000 THEN
          v_movil := ROUND(v_sum * v_porcetajes_mov(4) / 100);  -- 7%
           ELSIF v_prof.cod_comuna = 89 AND v_sum < 680000 THEN
          v_movil := ROUND(v_sum * v_porcetajes_mov(5) / 100);  -- 9%
          ELSE
          v_movil := 0;
          END IF;
    
          -- Calcular asignación por tipo de contrato (% sobre honorarios)
          IF v_prof.cod_comuna = 1 AND v_sum < 350000 THEN
          v_asig_tipo := ROUND(v_sum * v_porcetajes_tipo(1) / 100);  -- 15%
          ELSIF v_prof.cod_comuna = 2 THEN
          v_asig_tipo := ROUND(v_sum * v_porcetajes_tipo(2) / 100);  -- 10%
          ELSIF v_prof.cod_comuna = 3 AND v_sum < 400000 THEN
          v_asig_tipo := ROUND(v_sum * v_porcetajes_tipo(3) / 100);  -- 5%
          ELSIF v_prof.cod_comuna = 4 AND v_sum < 800000 THEN
          v_asig_tipo := ROUND(v_sum * v_porcetajes_tipo(4) / 100);  -- 5%
          ELSE
          v_asig_tipo := 0;
          END IF;  
    
          -- Calcular asignación por profesión (% sobre el sueldo)
          IF v_prof.cod_profesion = 1 THEN
          v_asig_prof := ROUND(v_sueldo * v_porcetajes_prof(1) / 100);  -- 12.3%
          ELSIF v_prof.cod_profesion = 3 THEN
          v_asig_prof := ROUND(v_sueldo * v_porcetajes_prof(2) / 100);  -- 14.36%
          ELSIF v_prof.cod_profesion = 4 THEN
          v_asig_prof := ROUND(v_sueldo * v_porcetajes_prof(3) / 100);  -- 21.34%
          ELSIF v_prof.cod_profesion = 5 THEN
          v_asig_prof := ROUND(v_sueldo * v_porcetajes_prof(4) / 100);  -- 14.32%
           ELSIF v_prof.cod_profesion = 6 THEN
          v_asig_prof := ROUND(v_sueldo * v_porcetajes_prof(5) / 100);  -- 22.44%
           ELSIF v_prof.cod_profesion = 7 THEN
          v_asig_prof := ROUND(v_sueldo * v_porcetajes_prof(4) / 100);  -- 12.36%
           ELSIF v_prof.cod_profesion = 8 THEN
          v_asig_prof := ROUND(v_sueldo * v_porcetajes_prof(5) / 100);  -- 18.23%
          ELSE
          v_asig_prof := 0;
          END IF;
          -- Total de asignaciones
          v_total := v_movil + v_asig_tipo + v_asig_prof;
    
          -- Verificar si el total excede el límite
          IF v_total > v_limite_asig THEN
            RAISE ex_limite_asig;
          END IF;
    
          -- Insertar en detalle_asignacion_mes
          INSERT INTO detalle_asignacion_mes (
            mes_proceso,
            anno_proceso,
            run_profesional,
            nombre_profesional,
            profesion,
            nro_asesorias,
            monto_honorarios,
            monto_movil_extra,
            monto_asig_tipocont,
            monto_asig_profesion,
            monto_total_asignaciones
          ) VALUES (
            v_mes,
            v_anno,
            v_profesional.numrun_prof,
            v_profesional.nombre || ' ' || v_profesional.appaterno || ' ' || v_profesional.apmaterno,
            v_profesional.nombre_profesion,
            v_count,
            v_sum,
            v_movil,
            v_asig_tipo,
            v_asig_prof,
            v_total
          );
    
        EXCEPTION
          -- Manejo del límite excedido
          WHEN ex_limite_asig THEN
            v_total := v_limite_asig;
            INSERT INTO errores_proceso
              (error_id, mensaje_error_oracle, mensaje_error_usr)
            VALUES
              (sq_error.NEXTVAL,
               NULL,
               'El monto total de asignaciones (' || (v_movil + v_asig_tipo + v_asig_prof) ||
               ') excede el límite de ' || v_limite_asig);
            -- Insertar con el total limitado
            INSERT INTO detalle_asignacion_mes (
              mes_proceso,
              anno_proceso,
              run_profesional,
              nombre_profesional,
              profesion,
              nro_asesorias,
              monto_honorarios,
              monto_movil_extra,
              monto_asig_tipocont,
              monto_asig_profesion,
              monto_total_asignaciones
            ) VALUES (
              v_mes,
              v_anno,
              v_profesional.numrun_prof,
              v_profesional.nombre || ' ' || v_profesional.appaterno || ' ' || v_profesional.apmaterno,
              v_profesional.nombre_profesion,
              v_count,
              v_sum,
              v_movil,
              v_asig_tipo,
              v_asig_prof,
              v_total
            );
    
          WHEN OTHERS THEN
            -- Cualquier otro error se registra y se continúa con el siguiente profesional
            INSERT INTO errores_proceso
              (error_id, mensaje_error_oracle, mensaje_error_usr)
            VALUES
              (sq_error.NEXTVAL,
               SQLERRM,
               'Error inesperado al procesar el profesional ' || v_profesional.numrun_prof);
        END; -- fin del bloque interno
    
      END LOOP; -- fin del cursor
    
      -- Generar el resumen por profesión a partir de los datos insertados
      INSERT INTO resumen_mes_profesion (
        anno_mes_proceso,
        profesion,
        total_asesorias,
        monto_total_honorarios,
        monto_total_movil_extra,
        monto_total_asig_tipocont,
        monto_total_asig_prof,
        monto_total_asignaciones
      )
      SELECT
        anno_proceso || mes_proceso,
        profesion,
        SUM(nro_asesorias),
        SUM(monto_honorarios),
        SUM(monto_movil_extra),
        SUM(monto_asig_tipocont),
        SUM(monto_asig_profesion),
        SUM(monto_total_asignaciones)
      FROM detalle_asignacion_mes
      WHERE mes_proceso = v_mes
        AND anno_proceso = v_anno
      GROUP BY profesion
      ORDER BY profesion;
    
      COMMIT;
    
      DBMS_OUTPUT.PUT_LINE('Proceso finalizado correctamente.');
    END;
    / 
    
    SELECT * FROM tipo_contrato;
    