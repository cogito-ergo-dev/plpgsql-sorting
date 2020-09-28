-- CREATE TRIGGER put_at_last
--    BEFORE INSERT ON persons
--    FOR EACH ROW EXECUTE PROCEDURE put_at_last();
CREATE OR REPLACE FUNCTION put_at_last() RETURNS trigger AS $$
DECLARE
    query TEXT;
    found INTEGER;
BEGIN
    IF TG_OP = 'INSERT' THEN
        query := 'SELECT COALESCE(MAX(sort), 0) + 1 FROM ' || quote_ident(TG_TABLE_NAME);
        EXECUTE query INTO found;
        NEW.sort := found;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;





CREATE OR REPLACE FUNCTION prev_next_simple_helper (
    IN arg_table_name TEXT
)
RETURNS TABLE (
    id          INTEGER,
    sort        INTEGER,
    prev_item   INTEGER,
    next_item   INTEGER,
    prev_sort   INTEGER,
    next_sort   INTEGER
) 
AS $$
DECLARE
    query TEXT;
BEGIN
    query := 'WITH cte AS (
        SELECT id, sort  
        FROM ' || quote_ident(arg_table_name) || '
        ORDER BY sort ASC
    )
    SELECT 
        *,
        LAG (id, 1) OVER (ORDER BY sort ASC) AS prev_item,
        LEAD (id, 1) OVER (ORDER BY sort ASC) AS next_item,
        LAG (sort, 1) OVER (ORDER BY sort ASC) AS prev_sort,
        LEAD (sort, 1) OVER (ORDER BY sort ASC) AS next_sort
    FROM cte;
    ';

	RETURN QUERY EXECUTE query;
END; $$ 

LANGUAGE 'plpgsql';




CREATE OR REPLACE FUNCTION move_simple(
    IN arg_way              TEXT,
    IN arg_table_name       TEXT,
    IN arg_item_id          INTEGER
)
RETURNS INTEGER AS $$
DECLARE
    v_min       INTEGER;
    v_max       INTEGER;

    v_sort_curr INTEGER;

    query_curr  TEXT;
    query_other TEXT;

    v_sort_other INTEGER;
    v_id_other   INTEGER;
BEGIN

    IF  NOT(arg_way = 'down' OR arg_way = 'up')
    THEN
        RAISE EXCEPTION 'You must select way as `up` or `down` only.';
    END IF;

    SELECT  MIN(sort), MAX(sort)
    INTO    v_min, v_max
    FROM    prev_next_simple_helper(arg_table_name);

    SELECT  sort
    INTO    v_sort_curr
    FROM    prev_next_simple_helper(arg_table_name)
    WHERE   id = arg_item_id;

    IF  (v_min = v_sort_curr AND arg_way = 'up')
        OR
        (v_max = v_sort_curr AND arg_way = 'down')
        THEN
        RAISE EXCEPTION 'You cannot up or down more this item.';
    END IF;

    SELECT
        CASE WHEN arg_way = 'up' THEN prev_sort ELSE next_sort END,
        CASE WHEN arg_way = 'up' THEN prev_item ELSE next_item END
    INTO
        v_sort_other,
        v_id_other
    FROM
        prev_next_simple_helper(arg_table_name)
    WHERE
        id = arg_item_id;

    query_curr := '
        UPDATE  '|| quote_ident(arg_table_name) ||'
        SET     sort = $1
        WHERE   id   = $2;
    ';

    query_other := '
        UPDATE  '|| quote_ident(arg_table_name) ||'
        SET     sort = $1
        WHERE   id   = $2;
    ';

    EXECUTE query_curr  USING v_sort_other, arg_item_id;
    EXECUTE query_other USING v_sort_curr, v_id_other;

    RETURN v_sort_other;
END;
$$ LANGUAGE plpgsql;







CREATE OR REPLACE FUNCTION sort_simple(
    IN arg_table_name       TEXT,
    IN arg_item_ids         TEXT
)
RETURNS VOID AS $$
DECLARE
    ids INTEGER[];
    i   INTEGER;
    id  INTEGER;
    nt  INTEGER;
    d   BOOLEAN;
    qn  TEXT;
    q   TEXT;
BEGIN
    ids := string_to_array(arg_item_ids, ',')::integer[];
    i   := 0;
    qn  := 'SELECT COUNT(*) FROM ' || quote_ident(arg_table_name);
    q   := 'UPDATE ' || quote_ident(arg_table_name) || ' SET sort=$1 WHERE id=$2';

    EXECUTE qn INTO nt;

    IF  nt <> cardinality(ids)
    THEN
        RAISE EXCEPTION 'IDS amount must be the same as amount of elements in the table.';
    END IF;

    -- Vérifions s’il y a des doublons avec un petit CTE des familles
    WITH dq AS (
        SELECT      item
        FROM        unnest(ids) AS item
        GROUP BY    item
        HAVING      count(*) > 1
    )
    SELECT  COUNT(*) > 0
    INTO    d
    FROM    dq;

    -- Alors docteur, doublon ou pas doublon ?
    IF  d
    THEN
        RAISE EXCEPTION 'IDS must be unique!';
    END IF;

    FOREACH id IN ARRAY ids
    LOOP
        i := i + 1;
        EXECUTE q USING i, id;
    END LOOP;
    
END;
$$ LANGUAGE plpgsql;








