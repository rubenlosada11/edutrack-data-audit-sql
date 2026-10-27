-- ============================================================
-- EduTrack — Auditoría de datos de la tabla enrollments
-- ============================================================
-- Consultas Q0–Q12 ejecutadas en Supabase (PostgreSQL), esquema EduTrack v2.
-- El script de creación y carga de datos se ejecutó aparte y no forma
-- parte de este archivo. Resultados documentados en analysis_report.md.
--
-- Ejecutar las consultas de una en una: Q7 (UPDATE) y Q8 (DELETE)
-- modifican datos. Q9–Q12 se calculan después de las correcciones Q6–Q8.
-- ============================================================

-- Q0: Comprobamos las primeras 5 inscripciones
SELECT * FROM enrollments LIMIT 5;


-- ------------------------------------------------------------
-- Q1: Inscripciones en 'Intro to Python'
-- Muestra nombre, email y % de completado de cada estudiante inscrito.
-- enrollments solo guarda IDs, así que unimos con students (nombre, email)
-- y con courses (título del curso, por el que filtramos).
-- ------------------------------------------------------------
SELECT s.name  AS student_name,
       s.email AS student_email,
       e.completion_percentage
FROM enrollments e
JOIN students s ON e.student_id = s.id
JOIN courses  c ON e.course_id  = c.id
WHERE c.title = 'Intro to Python';


-- ------------------------------------------------------------
-- Q2: Posibles abandonos
-- Inscripciones con completion_percentage estrictamente inferior a 10
-- (el 10 queda fuera). Se añaden estudiante y curso para poder actuar.
-- ------------------------------------------------------------
SELECT e.id    AS enrollment_id,
       s.name  AS student_name,
       c.title AS course_title,
       e.enrollment_date,
       e.completion_percentage
FROM enrollments e
JOIN students s ON e.student_id = s.id
JOIN courses  c ON e.course_id  = c.id
WHERE e.completion_percentage < 10
ORDER BY e.completion_percentage, e.enrollment_date;


-- ------------------------------------------------------------
-- Q3: Instructores sin asignar
-- En el esquema v2 el instructor está en courses.instructor_name
-- (única columna que admite NULL). Se usa IS NULL porque
-- "= NULL" nunca es verdadero.
-- ------------------------------------------------------------
SELECT e.id    AS enrollment_id,
       s.name  AS student_name,
       c.title AS course_title,
       c.instructor_name
FROM enrollments e
JOIN students s ON e.student_id = s.id
JOIN courses  c ON e.course_id  = c.id
WHERE c.instructor_name IS NULL;

-- Q3 (comprobación): instructor de cada curso y si SQL lo considera NULL
SELECT id, title, instructor_name,
       instructor_name IS NULL AS is_null
FROM courses
ORDER BY id;


-- ------------------------------------------------------------
-- Q4: Mejores porcentajes sin aprobar
-- Top 5 de completion_percentage entre inscripciones con passed = false.
-- Orden: WHERE filtra -> ORDER BY DESC ordena -> LIMIT corta.
-- e.id como segundo criterio para que el orden sea estable ante empates.
-- ------------------------------------------------------------
SELECT e.id    AS enrollment_id,
       s.name  AS student_name,
       c.title AS course_title,
       e.completion_percentage,
       e.passed
FROM enrollments e
JOIN students s ON e.student_id = s.id
JOIN courses  c ON e.course_id  = c.id
WHERE e.passed = false
ORDER BY e.completion_percentage DESC, e.id
LIMIT 5;


-- ------------------------------------------------------------
-- Q5: Inscripciones desde julio de 2024
-- ">=" incluye el propio 1 de julio (con ">" se perdería la inscripción
-- de ese día). Fecha en formato ISO 'AAAA-MM-DD'. Más reciente primero.
-- ------------------------------------------------------------
SELECT e.id    AS enrollment_id,
       s.name  AS student_name,
       c.title AS course_title,
       e.enrollment_date
FROM enrollments e
JOIN students s ON e.student_id = s.id
JOIN courses  c ON e.course_id  = c.id
WHERE e.enrollment_date >= '2024-07-01'
ORDER BY e.enrollment_date DESC;


-- ------------------------------------------------------------
-- Q6: INSERT de la inscripción faltante
-- INCIDENCIA: los datos de la inscripción confirmada por correo no
-- figuran en el script v2 ni en ninguna otra fuente disponible.
-- No se inserta ningún registro para no inventar datos.
-- ------------------------------------------------------------

-- Q6 (comprobación): estado actual de enrollments y de su contador de id
-- Resultado: 16 filas, max_id = 16, contador en last_value = 1 / is_called = false
SELECT (SELECT COUNT(*)   FROM enrollments)        AS total_enrollments,
       (SELECT MAX(id)    FROM enrollments)        AS max_id,
       (SELECT last_value FROM enrollments_id_seq) AS seq_last_value,
       (SELECT is_called  FROM enrollments_id_seq) AS seq_is_called;

-- Procedimiento preparado para cuando se disponga de los datos (NO ejecutado).
-- Sustituir los valores <...> por los datos confirmados.
--
-- 1) Obtener los id reales del estudiante y del curso:
-- SELECT id, name, email FROM students WHERE email = '<email>';
-- SELECT id, title, monthly_fee FROM courses WHERE title = '<título del curso>';
--
-- 2) Comprobar que la inscripción no existe ya (debe devolver 0 filas):
-- SELECT * FROM enrollments
-- WHERE student_id = <student_id> AND course_id = <course_id>;
--
-- 3) Sincronizar el contador de id con el máximo actual. Las filas se cargaron
--    con id explícito, lo que no avanza la secuencia; sin este paso el INSERT
--    generaría id = 1 y fallaría por clave duplicada:
-- SELECT setval('enrollments_id_seq', (SELECT MAX(id) FROM enrollments));
--
-- 4) Insertar sin indicar id (lo genera la secuencia). Las columnas omitidas
--    completion_percentage y passed tomarían su DEFAULT (0 y false):
-- INSERT INTO enrollments (student_id, course_id, enrollment_date,
--                          completion_percentage, passed, monthly_fee_paid)
-- VALUES (<student_id>, <course_id>, '<AAAA-MM-DD>', <0-100>, <true|false>, <importe>)
-- RETURNING *;
--
-- 5) Verificar: debe haber exactamente 1 fila nueva (total esperado: 17)
-- SELECT COUNT(*) FROM enrollments;


-- ------------------------------------------------------------
-- Q7: UPDATE de instructores NULL -> 'Pending assignment'
-- En v2 el instructor está en courses.instructor_name.
-- Protocolo: SELECT con el mismo WHERE -> UPDATE -> verificación.
-- ------------------------------------------------------------

-- Q7 (paso 1): filas que el UPDATE modificaría. Resultado: 0 filas
SELECT id, title, instructor_name
FROM courses
WHERE instructor_name IS NULL;

-- Q7 (paso 2): UPDATE con el mismo WHERE. RETURNING muestra las filas
-- modificadas. Resultado: 0 filas modificadas
UPDATE courses
SET instructor_name = 'Pending assignment'
WHERE instructor_name IS NULL
RETURNING id, title, instructor_name;

-- Q7 (paso 3): verificación. Resultado: 0 NULL, 1 'Pending assignment', 7 cursos
SELECT COUNT(*) FILTER (WHERE instructor_name IS NULL)                AS null_instructors,
       COUNT(*) FILTER (WHERE instructor_name = 'Pending assignment') AS pending_assignment,
       COUNT(*)                                                        AS total_courses
FROM courses;


-- ------------------------------------------------------------
-- Q8: DELETE de inscripciones de cuentas de prueba (@test.com)
-- Se borran inscripciones (enrollments), no estudiantes.
-- El patrón incluye la '@' para no capturar dominios como 'contest.com'.
-- Protocolo: SELECT con el mismo criterio -> DELETE -> verificación.
-- ------------------------------------------------------------

-- Q8 (paso 1a): inscripciones que borraría el DELETE. Resultado: 0 filas
SELECT e.id AS enrollment_id, s.id AS student_id, s.name, s.email, c.title AS course_title
FROM enrollments e
JOIN students s ON e.student_id = s.id
JOIN courses  c ON e.course_id  = c.id
WHERE s.email LIKE '%@test.com';

-- Q8 (paso 1b): control de variantes (mayúsculas, otros dominios con 'test').
-- No es el criterio de borrado. Resultado: 0 filas
SELECT id, name, email
FROM students
WHERE email ILIKE '%test%';

-- Q8 (paso 2): DELETE con el mismo criterio que 1a. Resultado: 0 filas eliminadas
DELETE FROM enrollments
WHERE student_id IN (
    SELECT id
    FROM students
    WHERE email LIKE '%@test.com'
)
RETURNING *;

-- Q8 (paso 3): verificación. Resultado: 16 inscripciones, 8 estudiantes, 0 de prueba
SELECT (SELECT COUNT(*) FROM enrollments)                       AS total_enrollments,
       (SELECT COUNT(*) FROM students)                          AS total_students,
       (SELECT COUNT(*)
          FROM enrollments e
          JOIN students s ON e.student_id = s.id
         WHERE s.email LIKE '%@test.com')                       AS test_enrollments_left;


-- ------------------------------------------------------------
-- Q9: Inscripciones por categoría
-- (Agregación calculada después de las correcciones Q6-Q8)
-- La categoría está en courses. COUNT(*) cuenta filas (inscripciones)
-- de cada grupo; cada columna del SELECT está en GROUP BY o es agregada.
-- ------------------------------------------------------------
SELECT c.category,
       COUNT(*) AS total_enrollments
FROM enrollments e
JOIN courses c ON e.course_id = c.id
GROUP BY c.category
ORDER BY total_enrollments DESC, c.category;


-- ------------------------------------------------------------
-- Q10: Promedio de completado por curso (de menor a mayor)
-- AVG ignora NULL (aquí no hay: la columna es NOT NULL).
-- ROUND(..., 2): promedio redondeado a 2 decimales.
-- Se agrupa por id y título para no mezclar cursos con el mismo nombre.
-- ------------------------------------------------------------
SELECT c.title AS course_title,
       COUNT(*) AS total_enrollments,
       ROUND(AVG(e.completion_percentage), 2) AS avg_completion
FROM enrollments e
JOIN courses c ON e.course_id = c.id
GROUP BY c.id, c.title
ORDER BY avg_completion ASC, c.title;


-- ------------------------------------------------------------
-- Q11: Cursos con más de tres inscripciones
-- HAVING filtra GRUPOS después de agrupar (WHERE no admite COUNT).
-- "> 3" es estricto: los cursos con exactamente 3 quedan fuera.
-- ------------------------------------------------------------
SELECT c.title AS course_title,
       COUNT(*) AS total_enrollments
FROM enrollments e
JOIN courses c ON e.course_id = c.id
GROUP BY c.id, c.title
HAVING COUNT(*) > 3
ORDER BY total_enrollments DESC, c.title;


-- ------------------------------------------------------------
-- Q12: Ingresos totales por categoría (de mayor a menor)
-- SUM de monthly_fee_paid (lo pagado por cada inscripción), no de
-- courses.monthly_fee (precio de catálogo). Tipo DECIMAL: suma exacta.
-- COUNT(*) se añade para comparar importe frente a número de inscripciones.
-- ------------------------------------------------------------
SELECT c.category,
       COUNT(*) AS total_enrollments,
       SUM(e.monthly_fee_paid) AS total_revenue
FROM enrollments e
JOIN courses c ON e.course_id = c.id
GROUP BY c.category
ORDER BY total_revenue DESC, c.category;