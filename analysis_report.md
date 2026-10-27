# Auditoría de datos — EduTrack (`enrollments`)

Informe de la auditoría de la tabla `enrollments` previa al ciclo de reporting del Q3.

## Contexto

- **Base de datos:** PostgreSQL (Supabase), esquema *EduTrack v2 — Normalized*.
- **Tablas:** `enrollments` (tabla auditada), `students` y `courses` (solo lectura).
- **Estado inicial:** 8 estudiantes, 7 cursos, 16 inscripciones.
- **Relaciones:** `enrollments.student_id → students.id` y `enrollments.course_id → courses.id`.
  Por eso los datos de estudiante (nombre, email) y de curso (título, categoría, instructor)
  se obtienen mediante `JOIN`.
- **Convenciones del informe:**
  - *Resultado observado*: cifras devueltas por Supabase al ejecutar las consultas de `queries.sql`.
  - *Cifras derivadas*: cálculos hechos a partir de esos resultados (porcentajes, totales); se indican como tales.
  - *Interpretación*: lectura de los resultados. Cuando se apoya en el script de carga (`edutrack_v2.sql`)
    y no en una consulta ejecutada, se indica expresamente.
  - Los decimales se escriben con punto, igual que en la salida de Supabase.

---

## Resumen de la auditoría

| Q   | Tema                                   | Resultado principal |
|-----|----------------------------------------|---------------------|
| Q1  | Inscripciones en Intro to Python       | 4 inscripciones |
| Q2  | Posibles abandonos (< 10 %)            | 5 inscripciones (31 % del total) |
| Q3  | Instructores sin asignar (NULL)        | 0 inscripciones |
| Q4  | Mejores porcentajes sin aprobar        | 60, 55, 45, 40 y 20 % (4 estudiantes distintos) |
| Q5  | Inscripciones desde julio de 2024      | 10 inscripciones |
| Q6  | Inscripción faltante                   | **No ejecutada**: datos no disponibles; 0 filas insertadas |
| Q7  | Corrección de instructores             | 0 filas modificadas |
| Q8  | Eliminación de cuentas de prueba       | 0 filas eliminadas |
| Q9  | Inscripciones por categoría            | Programming 7, Design 4, Data 3, Marketing 2 |
| Q10 | Promedio de completado por curso       | De 0.00 (UI/UX Fundamentals) a 80.00 (Intro to Python) |
| Q11 | Cursos con más de tres inscripciones   | 1 curso: Intro to Python (4) |
| Q12 | Ingresos por categoría                 | Programming 409.93, Data 179.97, Design 169.96, Marketing 59.98 |

**Hallazgos principales:**
- **Calidad de datos:** no hay instructores `NULL` ni cuentas de prueba. Las correcciones Q7 y Q8
  se ejecutaron con doble comprobación y no afectaron a ninguna fila. Los datos quedan en
  16 inscripciones, 8 estudiantes y 7 cursos.
- **Incidencias:** la inscripción faltante (Q6) no pudo registrarse por falta de datos de origen.
  Además, el contador de `id` de `enrollments` está desincronizado: cualquier `INSERT` futuro sin `id`
  fallaría hasta corregirlo.
- **Riesgo de abandono:** 5 de 16 inscripciones están por debajo del 10 %. Se concentran en una
  estudiante (Lucia Fernandes, 3 casos) y en UI/UX Fundamentals (promedio 0.00, instructor
  *Pending assignment*).
- **Negocio:** Programming reúne 7 de 16 inscripciones y el 50 % del importe mensual. Intro to Python
  es el curso más sólido: el que más inscripciones tiene (4) y el de mayor promedio (80.00).

---

## Q1 - Inscripciones en Intro to Python

**Objetivo:** listar todas las inscripciones del curso *Intro to Python* con el nombre,
el email y el porcentaje de completado de cada estudiante.

**Consulta:** `JOIN` de `enrollments` con `students` y `courses`, filtrando por
`courses.title = 'Intro to Python'`.

**Resultado observado:** 4 inscripciones.

| student_name | student_email                     | completion_percentage |
|--------------|-----------------------------------|----------------------:|
| Emily Watson | emily.watson@student.edutrack.com | 85                    |
| Klaus Weber  | klaus.weber@student.edutrack.com  | 92                    |
| Marco Rossi  | marco.rossi@student.edutrack.com  | 88                    |
| Priya Sharma | priya.sharma@student.edutrack.com | 55                    |

Columnas devueltas: `student_name`, `student_email`, `completion_percentage`.

**Interpretación:**
- Las 4 filas coinciden con las inscripciones del curso 1 presentes en los datos de carga,
  lo que confirma que los `JOIN` emparejan correctamente cada inscripción con su estudiante y su curso.
- Tres de los cuatro estudiantes superan el 85 % de completado (85, 88 y 92).
  Priya Sharma está claramente por detrás, con un 55 %.

---

## Q2 - Posibles abandonos

**Objetivo:** identificar las inscripciones con `completion_percentage` inferior a 10
(condición estricta `< 10`).

**Consulta:** filtro `WHERE e.completion_percentage < 10`, con `JOIN` a `students` y `courses`
para identificar estudiante y curso; ordenado por porcentaje y fecha de inscripción.

**Resultado observado:** 5 inscripciones (31 % de las 16 inscripciones).

| enrollment_id | student_name    | course_title          | enrollment_date | completion_percentage |
|--------------:|-----------------|-----------------------|-----------------|----------------------:|
| 10            | Yuki Nakamura   | UI/UX Fundamentals    | 2024-10-11      | 0                     |
| 11            | Pierre Dubois   | UI/UX Fundamentals    | 2024-11-05      | 0                     |
| 16            | Lucia Fernandes | Advanced Python       | 2025-04-01      | 0                     |
| 6             | Lucia Fernandes | Digital Marketing 101 | 2024-07-01      | 3                     |
| 5             | Lucia Fernandes | Web Design Basics     | 2024-06-20      | 5                     |

- 3 inscripciones con 0 %, 1 con 3 % y 1 con 5 %.
- Ninguna inscripción tiene exactamente un 10 %, por lo que en estos datos `< 10` y `<= 10`
  devolverían lo mismo; se usa `<` porque es lo que exige el criterio.
- `completion_percentage` es `NOT NULL`, así que no hay inscripciones excluidas por valores nulos.

**Interpretación:**
- **Lucia Fernandes** aparece 3 veces, en tres cursos distintos. Según el script de carga, son todas
  sus inscripciones. Es un caso de riesgo de abandono a nivel de estudiante, no de un curso concreto.
- **UI/UX Fundamentals** tiene sus 2 inscripciones con 0 % de avance. Es el curso cuyo instructor
  figura como *Pending assignment* en `courses`; la coincidencia sugiere que la falta de instructor
  podría estar frenando el curso, aunque con dos registros no puede afirmarse una causa.

---

## Q3 - Instructores sin asignar

**Objetivo:** identificar las inscripciones cuyo instructor es `NULL`.

**Consulta:** en el esquema v2 el instructor se guarda en `courses.instructor_name`, así que se
une `enrollments` con `courses` y se filtra con `WHERE c.instructor_name IS NULL`.
Se añade una consulta de comprobación sobre `courses` que muestra, para cada curso,
si SQL considera su instructor como `NULL`.

**Resultado observado:**
- Consulta principal: **0 filas**. Ninguna inscripción tiene instructor `NULL`.
- Comprobación sobre `courses` (7 cursos, `is_null = false` en todos):

| id | title                  | instructor_name    | is_null |
|---:|------------------------|--------------------|---------|
| 1  | Intro to Python        | Marta López        | false   |
| 2  | Web Design Basics      | Carlos Vega        | false   |
| 3  | Data Analysis with SQL | Marta López        | false   |
| 4  | Digital Marketing 101  | Lucia Prades       | false   |
| 5  | Advanced Python        | Carlos Vega        | false   |
| 6  | UI/UX Fundamentals     | Pending assignment | false   |
| 7  | Email Campaigns        | Lucia Prades       | false   |

**Registros potencialmente afectados por la corrección posterior (Q7):** 0.

**Interpretación:**
- No hay valores `NULL` de instructor en los datos actuales.
- El único curso sin instructor real es **UI/UX Fundamentals**, que ya figura con el texto
  `'Pending assignment'`. Para SQL es un texto, no un `NULL`, por eso no aparece en la consulta
  principal. Este valor es precisamente el que Q7 debía asignar, lo que indica que en la versión
  v2 de los datos la corrección ya viene aplicada.
- Esto confirma lo señalado en Q2: las dos inscripciones al 0 % de UI/UX Fundamentals
  corresponden al curso pendiente de asignar instructor.

---

## Q4 - Mejores porcentajes sin aprobar

**Objetivo:** mostrar los cinco mayores porcentajes de completado entre las inscripciones
que todavía no han aprobado.

**Consulta:** `WHERE e.passed = false`, `ORDER BY e.completion_percentage DESC, e.id` y `LIMIT 5`,
con `JOIN` a `students` y `courses` para identificar estudiante y curso.

**Resultado observado:** 5 filas.

| enrollment_id | student_name  | course_title           | completion_percentage | passed |
|--------------:|---------------|------------------------|----------------------:|--------|
| 2             | Emily Watson  | Web Design Basics      | 60                    | false  |
| 13            | Priya Sharma  | Intro to Python        | 55                    | false  |
| 9             | Yuki Nakamura | Data Analysis with SQL | 45                    | false  |
| 15            | Emily Watson  | Advanced Python        | 40                    | false  |
| 14            | Pierre Dubois | Data Analysis with SQL | 20                    | false  |

- Las 5 filas corresponden a **4 estudiantes distintos**: Emily Watson aparece con dos inscripciones.
- **No hay empate oculto en el corte:** ante un empate a 20 % se ordena por `id`, de modo que solo
  podría quedar fuera una inscripción con `id` mayor que 14. Las inscripciones 15 (40 %, en esta
  tabla) y 16 (0 %, en Q2) descartan esa posibilidad.

**Interpretación:**
- El resultado es un ranking de **inscripciones**, no de estudiantes. Si se quisiera un estudiante
  por fila, Emily Watson ocuparía una sola posición y entraría un sexto registro.
- Ninguna inscripción no aprobada supera el 60 %: no hay casos "a punto de terminar" sin aprobar.
- Priya Sharma (55 %) es la única de *Intro to Python* que no ha aprobado, en línea con Q1,
  donde era la que tenía menor avance del curso.

---

## Q5 - Inscripciones desde julio de 2024

**Objetivo:** obtener las inscripciones con fecha igual o posterior al 1 de julio de 2024,
ordenadas de más reciente a más antigua.

**Consulta:** `WHERE e.enrollment_date >= '2024-07-01'` y `ORDER BY e.enrollment_date DESC`,
con `JOIN` a `students` y `courses`.

**Resultado observado:** 10 inscripciones (de 16).

| enrollment_id | student_name    | course_title           | enrollment_date |
|--------------:|-----------------|------------------------|-----------------|
| 16            | Lucia Fernandes | Advanced Python        | 2025-04-01      |
| 15            | Emily Watson    | Advanced Python        | 2025-03-05      |
| 14            | Pierre Dubois   | Data Analysis with SQL | 2025-02-20      |
| 13            | Priya Sharma    | Intro to Python        | 2025-01-10      |
| 12            | Priya Sharma    | Digital Marketing 101  | 2024-12-01      |
| 11            | Pierre Dubois   | UI/UX Fundamentals     | 2024-11-05      |
| 10            | Yuki Nakamura   | UI/UX Fundamentals     | 2024-10-11      |
| 9             | Yuki Nakamura   | Data Analysis with SQL | 2024-09-03      |
| 8             | Marco Rossi     | Intro to Python        | 2024-08-09      |
| 6             | Lucia Fernandes | Digital Marketing 101  | 2024-07-01      |

- Rango: de 2024-07-01 a 2025-04-01. Inscripción más reciente: id 16.
- La inscripción 6 tiene fecha **exactamente** 2024-07-01: entra gracias al operador `>=`.
  Con `>` el resultado habría sido de 9 filas.
- Las 6 inscripciones restantes son anteriores a julio de 2024.

**Interpretación:**
- La mayoría de la actividad registrada (10 de 16 inscripciones, 62.5 %) es de julio de 2024 en adelante,
  con un ritmo aproximado de una inscripción al mes.
- 4 de los 5 posibles abandonos detectados en Q2 (ids 6, 10, 11 y 16) son inscripciones de este
  periodo; solo la inscripción 5 (2024-06-20) es anterior. El riesgo de abandono se concentra
  en las inscripciones más recientes, aunque en las más nuevas parte del bajo avance puede deberse
  simplemente a que llevan menos tiempo en el curso.

---

## Q6 - Inscripción faltante

**Objetivo:** añadir la inscripción confirmada por correo que no se registró en la base de datos.

**⚠️ Incidencia: operación no ejecutada.**
Según el briefing, los datos de esta inscripción figuraban en un comentario del script original.
La base de datos se cargó con el script *EduTrack v2*, que no contiene ese comentario, y no existe
otra fuente disponible (versión anterior, enunciado o correo) con los datos. Para no introducir
registros inventados en una auditoría, **no se ha insertado ninguna fila**.

**Resultado observado (comprobación de solo lectura):**

| total_enrollments | max_id | seq_last_value | seq_is_called |
|------------------:|-------:|---------------:|---------------|
| 16                | 16     | 1              | false         |

- Filas insertadas: **0**.
- Total de inscripciones tras Q6: **16** (sin cambios).

**Hallazgo técnico: contador de `id` desincronizado.**
Los registros se cargaron indicando el `id` explícitamente, lo que no hace avanzar la secuencia
`enrollments_id_seq`. Con `last_value = 1` e `is_called = false`, el próximo `id` automático sería 1,
que ya existe: **cualquier `INSERT` sin `id` fallaría por clave primaria duplicada**.

**Recomendación:** antes de la próxima inserción, sincronizar la secuencia con el máximo actual
(`setval('enrollments_id_seq', MAX(id))`). El procedimiento completo (comprobación de duplicados,
sincronización, `INSERT ... RETURNING *` y verificación) queda preparado y comentado en `queries.sql`
para ejecutarse en cuanto se disponga de los datos confirmados.

**Impacto en el resto del informe:** las agregaciones (Q9–Q12) se calculan sin esta inscripción.
Si se incorporase más adelante, deberían recalcularse.

---

## Q7 - Corrección de instructores

**Objetivo:** asignar el valor `'Pending assignment'` a todos los instructores `NULL`.

**Consulta:** en el esquema v2 el instructor está en `courses.instructor_name`. Se siguió el
protocolo de doble comprobación:
1. `SELECT` previo con `WHERE instructor_name IS NULL` para identificar las filas afectadas.
2. `UPDATE courses SET instructor_name = 'Pending assignment' WHERE instructor_name IS NULL`
   con el mismo `WHERE` y `RETURNING` para ver las filas modificadas.
3. Verificación posterior con recuentos sobre `courses`.

**Resultado observado:**
- Filas identificadas inicialmente (paso 1): **0**.
- Filas modificadas por el `UPDATE` (paso 2): **0** (`RETURNING` no devolvió ninguna fila).
- Valor que se habría asignado: `'Pending assignment'`.
- Verificación posterior (paso 3):

| null_instructors | pending_assignment | total_courses |
|-----------------:|-------------------:|--------------:|
| 0                | 1                  | 7             |

**Interpretación:**
- No quedan instructores `NULL`. El único curso con `'Pending assignment'` es UI/UX Fundamentals,
  que ya tenía ese valor antes del `UPDATE` (ver Q3).
- Al no haber filas afectadas, la tabla `courses` no ha sufrido ninguna modificación, en línea con
  la indicación del briefing de no alterar `students` ni `courses`.
- La corrección que pedía Q7 ya viene aplicada en los datos v2. El `UPDATE` queda en `queries.sql`
  como control: si en el futuro apareciera algún instructor `NULL`, la misma sentencia lo corregiría.

---

## Q8 - Eliminación de cuentas de prueba

**Objetivo:** eliminar las inscripciones ligadas a estudiantes cuyo email termina en `@test.com`.

**Consulta:** protocolo de doble comprobación:
1. `SELECT` previo de las inscripciones con `students.email LIKE '%@test.com'` (criterio exacto),
   más un control amplio `email ILIKE '%test%'` para detectar variantes (mayúsculas u otros dominios).
2. `DELETE FROM enrollments WHERE student_id IN (SELECT id FROM students WHERE email LIKE '%@test.com')`
   con el mismo criterio y `RETURNING *`.
3. Verificación posterior de recuentos.

El patrón incluye la `@` para no afectar a dominios legítimos que terminen en "test.com"
(por ejemplo, `contest.com`). Solo se borran filas de `enrollments`; `students` no se modifica.

**Resultado observado:**
- Inscripciones detectadas con el criterio exacto (paso 1a): **0**.
- Emails con "test" en cualquier variante (paso 1b): **0**. No hay casos ambiguos.
- Inscripciones eliminadas (paso 2): **0** (`RETURNING` no devolvió ninguna fila).
- Verificación posterior (paso 3):

| total_enrollments | total_students | test_enrollments_left |
|------------------:|---------------:|----------------------:|
| 16                | 8              | 0                     |

**Interpretación:**
- No existen cuentas de prueba en los datos: ningún email de los 8 estudiantes contiene "test",
  lo que coincide con lo indicado en el script v2 ("sin cuentas de prueba importadas").
- La tabla `enrollments` mantiene sus 16 inscripciones y `students` sus 8 estudiantes.
- Incidencias: ninguna. El `DELETE` queda en `queries.sql` como control para futuras cargas de datos.

---

**Estado de los datos tras las correcciones (Q6–Q8):** 16 inscripciones, 8 estudiantes y 7 cursos,
sin cambios respecto al estado inicial. Las agregaciones siguientes (Q9–Q12) se calculan sobre este estado.

---

## Q9 - Inscripciones por categoría

**Objetivo:** contar el número de inscripciones de cada categoría.

**Consulta:** `JOIN` de `enrollments` con `courses` (donde está `category`), `GROUP BY c.category`
y `COUNT(*)`, ordenado de mayor a menor número de inscripciones.

**Resultado observado:** 4 categorías.

| category    | total_enrollments | % del total |
|-------------|------------------:|------------:|
| Programming | 7                 | 43.75 %     |
| Design      | 4                 | 25.00 %     |
| Data        | 3                 | 18.75 %     |
| Marketing   | 2                 | 12.50 %     |
| **Total**   | **16**            | 100 %       |

- La suma de los recuentos (16) coincide con el total de inscripciones: ninguna se pierde ni se
  duplica en el `JOIN`.
- Los porcentajes se han calculado a partir de los recuentos observados.

**Interpretación:**
- **Programming** concentra casi la mitad de las inscripciones (7 de 16).
- **Marketing** es la categoría con menos demanda (2 inscripciones).
- De las 4 inscripciones de **Design**, 2 son de UI/UX Fundamentals (curso de la categoría Design
  según el script de carga) con 0 % de avance (Q2): la mitad de la actividad de la categoría está,
  de momento, parada.

---

## Q10 - Promedio de completado por curso

**Objetivo:** calcular el promedio de `completion_percentage` por curso, ordenado de menor a mayor.

**Consulta:** `JOIN` de `enrollments` con `courses`, `GROUP BY c.id, c.title`,
`ROUND(AVG(e.completion_percentage), 2)` y `ORDER BY avg_completion ASC`. Se añade `COUNT(*)`
para dar contexto sobre cuántas inscripciones respaldan cada media.

**Precisión:** promedios redondeados a **2 decimales**.

**Resultado observado:** 6 cursos.

| course_title           | total_enrollments | avg_completion |
|------------------------|------------------:|---------------:|
| UI/UX Fundamentals     | 2                 | 0.00           |
| Web Design Basics      | 2                 | 32.50          |
| Digital Marketing 101  | 2                 | 36.50          |
| Advanced Python        | 3                 | 45.00          |
| Data Analysis with SQL | 3                 | 47.67          |
| Intro to Python        | 4                 | 80.00          |

- La suma de inscripciones (16) coincide con el total.
- El promedio de Intro to Python (80.00) es coherente con los porcentajes individuales de Q1
  (85, 92, 88 y 55).
- No aparece *Email Campaigns*: al no tener inscripciones, el `INNER JOIN` no genera filas para él
  y no hay valores sobre los que calcular una media.
- `completion_percentage` es `NOT NULL`, así que todas las inscripciones intervienen en los promedios.

**Interpretación:**
- **Intro to Python** es el único curso con un promedio superior al 50 %; los otros cinco están por debajo.
- **UI/UX Fundamentals** tiene un promedio de 0: ninguno de sus alumnos ha avanzado (ver Q2 y Q3).
- Las medias se basan en 2–4 inscripciones por curso, por lo que un solo valor extremo las desplaza
  mucho. Por ejemplo, el 32.50 de Web Design Basics resulta de una inscripción al 5 % (Q2) y otra al 60 % (Q4).

---

## Q11 - Cursos con más de tres inscripciones

**Objetivo:** mostrar únicamente los cursos con más de tres inscripciones.

**Consulta:** `JOIN` de `enrollments` con `courses`, `GROUP BY c.id, c.title` y
`HAVING COUNT(*) > 3`. Se usa `HAVING` y no `WHERE` porque la condición se aplica sobre el
recuento de cada grupo, que solo existe después de agrupar.

**Resultado observado:** 1 curso.

| course_title    | total_enrollments |
|-----------------|------------------:|
| Intro to Python | 4                 |

- Quedan excluidos **Advanced Python** y **Data Analysis with SQL**, con exactamente 3 inscripciones
  cada uno (según Q10): el criterio es estrictamente mayor que 3.
- El resto de cursos con inscripciones tiene 2 (Q10).

**Interpretación:**
- **Intro to Python** es el curso con más inscripciones (4) y, según Q10, también el de mayor
  promedio de completado (80.00): es el curso más sólido del catálogo.
- La demanda está muy repartida: ningún otro curso supera las 3 inscripciones.

---

## Q12 - Ingresos por categoría

**Objetivo:** calcular los ingresos totales (`SUM` de `monthly_fee_paid`) por categoría,
ordenados de mayor a menor.

**Consulta:** `JOIN` de `enrollments` con `courses`, `GROUP BY c.category`,
`SUM(e.monthly_fee_paid)` y `ORDER BY total_revenue DESC`. Se añade `COUNT(*)` para comparar
importes con número de inscripciones.

**Qué representa la cifra:** `monthly_fee_paid` es la **cuota mensual** pagada en cada inscripción
(un único importe por fila). La suma equivale al **importe mensual agregado** de las inscripciones
registradas; no es el ingreso histórico acumulado (no refleja cuántos meses ha pagado cada
inscripción) ni confirma que todas sigan activas.

**Resultado observado:** 4 categorías.

| category    | total_enrollments | total_revenue |
|-------------|------------------:|--------------:|
| Programming | 7                 | 409.93        |
| Data        | 3                 | 179.97        |
| Design      | 4                 | 169.96        |
| Marketing   | 2                 | 59.98         |

**Cifras derivadas** (calculadas a partir de la tabla anterior):

| category    | % del importe total | importe medio por inscripción |
|-------------|--------------------:|------------------------------:|
| Programming | 50.00 %             | 58.56                         |
| Data        | 21.95 %             | 59.99                         |
| Design      | 20.73 %             | 42.49                         |
| Marketing   | 7.32 %              | 29.99                         |

Importe total (suma de las cuatro categorías): **819.84**.

- Los recuentos coinciden con Q9 (7, 4, 3 y 2; total 16).
- `monthly_fee_paid` es `NOT NULL`: todas las inscripciones contribuyen a la suma.

**Interpretación:**
- **Programming** genera la mitad del importe (50.00 %), en línea con ser la categoría con más
  inscripciones (Q9).
- **Data supera a Design** en importe (179.97 frente a 169.96) teniendo menos inscripciones
  (3 frente a 4): su importe medio por inscripción es mayor. Contar inscripciones y sumar importes
  ofrecen rankings distintos.
- **Marketing** es la categoría con menor peso tanto en inscripciones como en importe.
- Una parte del importe de Design procede de UI/UX Fundamentals (categoría Design según el script
  de carga), cuyos alumnos están al 0 % de avance (Q2): son ingresos asociados a un curso sin
  instructor asignado (Q3) y con riesgo de abandono.
