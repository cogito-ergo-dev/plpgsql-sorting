-- CREATE TRIGGER put_at_last
--    BEFORE INSERT ON players
--    FOR EACH ROW EXECUTE PROCEDURE put_at_last_into_container('team_id');
CREATE OR REPLACE FUNCTION put_at_last_into_container() RETURNS trigger AS $$
DECLARE
    query TEXT;
    found INTEGER;
BEGIN
    IF TG_OP = 'INSERT' THEN
        query := 'SELECT COALESCE(MAX(sort), 0) + 1 FROM ' || quote_ident(TG_TABLE_NAME);
        query := query || ' WHERE '|| quote_ident(TG_ARGV[0] :: text) ||' = $1.' ||TG_ARGV[0] :: text;
        
        EXECUTE query USING NEW INTO found;

        NEW.sort := found;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION prev_next_in_container_helper (
    IN arg_table_name       TEXT,
    IN arg_container_field  TEXT,
    IN arg_item_field       TEXT
)
RETURNS TABLE (
    container_id    INTEGER,
    item_id         INTEGER,
    sort            INTEGER,
    prev_item       INTEGER,
    next_item       INTEGER,
    prev_sort       INTEGER,
    next_sort       INTEGER
) 
AS $$
DECLARE
    query TEXT;
BEGIN
    query := 'WITH cte AS (
        SELECT      '|| quote_ident(arg_container_field) || ',
                    '|| quote_ident(arg_item_field) || ',
                    sort  
        FROM        '|| quote_ident(arg_table_name) || '
        ORDER BY    sort ASC
    )
    SELECT 
        *,

        LAG (' || quote_ident(arg_item_field) || ', 1)
        OVER (
            PARTITION BY '|| quote_ident(arg_container_field) || ' 
            ORDER BY sort ASC
        ) AS prev_item,

        LEAD (' || quote_ident(arg_item_field) || ', 1) 
        OVER (
            PARTITION BY '|| quote_ident(arg_container_field) || ' 
            ORDER BY sort ASC
        ) AS next_item,

        LAG (sort, 1)
        OVER (
            PARTITION BY '|| quote_ident(arg_container_field) || ' 
            ORDER BY sort ASC
        ) AS prev_sort,

        LEAD (sort, 1)
        OVER (
            PARTITION BY '|| quote_ident(arg_container_field) || ' 
            ORDER BY sort ASC
        ) AS next_sort

    FROM cte;
    ';

	RETURN QUERY EXECUTE query;
END; $$ 

LANGUAGE 'plpgsql';


CREATE OR REPLACE FUNCTION move_in_container(
    IN arg_way              TEXT,
    IN arg_table_name       TEXT,
    IN arg_container_field  TEXT,
    IN arg_item_field       TEXT,
    IN arg_container_id     INTEGER,
    IN arg_item_id          INTEGER
)
RETURNS INTEGER AS $$
DECLARE
    v_min           INTEGER;
    v_max           INTEGER;
    v_sort_curr     INTEGER;
    query_curr      TEXT;
    query_other     TEXT;
    v_sort_other    INTEGER DEFAULT 0;
    v_id_other      INTEGER;
BEGIN
    IF  NOT(arg_way = 'down' OR arg_way = 'up')
    THEN
        RAISE EXCEPTION 'You must select way as `up` or `down` only.';
    END IF;

    SELECT  MIN(sort), MAX(sort)
    INTO    v_min, v_max
    FROM    prev_next_in_container_helper(
                arg_table_name,
                arg_container_field,
                arg_item_field
            )
    WHERE   container_id = arg_container_id;

    SELECT  sort
    INTO    v_sort_curr
    FROM    prev_next_in_container_helper(
                arg_table_name,
                arg_container_field,
                arg_item_field
            )
    WHERE   item_id = arg_item_id
            AND
            container_id = arg_container_id;

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
        prev_next_multiple_helper(
            arg_table_name,
            arg_container_field,
            arg_item_field
        )
    WHERE
        item_id = arg_item_id
        AND
        container_id = arg_container_id;

    query_curr := '
        UPDATE  '|| quote_ident(arg_table_name) ||'
        SET     sort = $1
        WHERE   '|| quote_ident(arg_item_field) ||' = $2
                AND
                '|| quote_ident(arg_container_field) ||' = $3;
    '
    ;
    query_other := '
        UPDATE  '|| quote_ident(arg_table_name) ||'
        SET     sort = $1
        WHERE   '|| quote_ident(arg_item_field) ||' = $2
                AND
                '|| quote_ident(arg_container_field) ||' = $3;
    '
    ;

    EXECUTE query_curr  USING v_sort_other, arg_item_id, arg_container_id;
    EXECUTE query_other USING v_sort_curr, v_id_other, arg_container_id;

    RETURN v_sort_other;
END;
$$ LANGUAGE plpgsql;




CREATE OR REPLACE FUNCTION sort_in_container(
    IN arg_table_name       TEXT,
    IN arg_container_field  TEXT,
    IN arg_item_field       TEXT,
    IN arg_container_id     INTEGER,
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

    -- Pour les deux requêtes, on précise le conteneur…
    qn  := 'SELECT COUNT(*) FROM ' || quote_ident(arg_table_name);
    qn  := qn || ' WHERE ' || quote_ident(arg_container_field) ||' = $1';

    q   := 'UPDATE ' || quote_ident(arg_table_name);
    q   := q || ' SET sort=$1 WHERE ' || quote_ident(arg_item_field) || '=$2';
    q   := q || ' AND ' || quote_ident(arg_container_field) ||' = $3';

    EXECUTE qn INTO nt USING arg_container_id;

    IF  nt <> cardinality(ids)
    THEN
        RAISE EXCEPTION 'IDS amount must be the same as amount of elements inside the container.';
    END IF;

    WITH dq AS (
        SELECT      item
        FROM        unnest(ids) AS item
        GROUP BY    item
        HAVING      count(*) > 1
    )
    SELECT  COUNT(*) > 0
    INTO    d
    FROM    dq;

    IF  d
    THEN
        RAISE EXCEPTION 'IDS must be unique inside the container!';
    END IF;

    FOREACH id IN ARRAY ids
    LOOP
        i := i + 1;
        EXECUTE q USING i, id, arg_container_id;
    END LOOP;
    
END;
$$ LANGUAGE plpgsql;

