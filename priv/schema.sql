-- CREATE DATABASE metric_metadata;
CREATE USER ddb WITH PASSWORD 'ddb';
CREATE DATABASE metric_metadata OWNER ddb;
GRANT ALL ON DATABASE metric_metadata TO ddb;
\connect metric_metadata;

CREATE TABLE metrics (
    id          bigserial PRIMARY key,
    collection  varchar NOT NULL,
    metric      varchar NOT NULL,
    bucket      varchar NOT NULL,
    key         varchar NOT NULL
);
GRANT ALL On metrics TO ddb;
GRANT ALL On metrics_id_seq TO ddb;

CREATE UNIQUE INDEX metrics_idx ON metrics (collection, metric, bucket, key);

CREATE FUNCTION add_metric(acollection text, ametric text, abucket text, akey text) RETURNS bigint AS
$$
DECLARE aid integer;
BEGIN
    LOOP
        -- first try to update the key
        -- note that "a" must be unique
        SELECT id FROM metrics INTO aid WHERE collection = acollection
          AND metric = ametric
          AND bucket = abucket
          AND key = akey;
        IF found THEN
            RETURN aid;
        END IF;
        -- not there, so try to insert the key
        -- if someone else inserts the same key concurrently,
        -- we could get a unique-key failure
        BEGIN
            INSERT INTO metrics (collection, metric, bucket, key) VALUES (acollection, ametric, abucket, akey) RETURNING id INTO aid;
            RETURN aid;
        EXCEPTION WHEN unique_violation THEN
            -- do nothing, and loop to try the UPDATE again
        END;
    END LOOP;
END;
$$
LANGUAGE plpgsql;

CREATE TABLE tags (
    metric_id bigserial REFERENCES metrics (id) ON DELETE CASCADE,
    namespace   text NOT NULL,
    name        text NOT NULL,
    value       text NOT NULL
);

GRANT ALL On tags TO ddb;

CREATE UNIQUE INDEX tags_idx ON tags (metric_id, namespace, name, value);
CREATE UNIQUE INDEX tags_name_idx ON tags (metric_id, namespace, name);
CREATE INDEX tags_idx_name ON TAGS (namespace, name);
CREATE INDEX tags_idx_value ON TAGS (value);

CREATE FUNCTION add_tag(ametric_id bigint, anamespace text, aname text, avalue text) RETURNS VOID AS
$$
DECLARE aid integer;
BEGIN
    LOOP
        -- first try to update the key
        -- note that "a" must be unique
        PERFORM FROM tags WHERE metric_id = ametric_id
          AND namespace = anamespace
          AND name = aname
          AND value = avalue;
        IF found THEN
            RETURN;
        END IF;
        -- not there, so try to insert the key
        -- if someone else inserts the same key concurrently,
        -- we could get a unique-key failure
        BEGIN
            INSERT INTO tags (metric_id, namespace, name, value)
              VALUES (ametric_id, anamespace, aname, avalue);
            RETURN;
        EXCEPTION WHEN unique_violation THEN
            -- do nothing, and loop to try the UPDATE again
        END;
    END LOOP;
END;
$$
LANGUAGE plpgsql;
