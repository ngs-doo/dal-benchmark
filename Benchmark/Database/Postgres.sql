DO $$ BEGIN
	IF EXISTS(SELECT * FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = '-NGS-' AND c.relname = 'database_setting') THEN	
		IF EXISTS(SELECT * FROM "-NGS-".Database_Setting WHERE Key ILIKE 'mode' AND NOT Value ILIKE 'unsafe') THEN
			RAISE EXCEPTION 'Database upgrade is forbidden. Change database mode to allow upgrade';
		END IF;
	END IF;
END $$ LANGUAGE plpgsql;
CREATE EXTENSION IF NOT EXISTS hstore;

DO $$
DECLARE script VARCHAR;
BEGIN
	IF NOT EXISTS(SELECT * FROM pg_namespace WHERE nspname = '-NGS-') THEN
		CREATE SCHEMA "-NGS-";
		COMMENT ON SCHEMA "-NGS-" IS 'NGS generated';
	END IF;
	IF NOT EXISTS(SELECT * FROM pg_namespace WHERE nspname = 'public') THEN
		CREATE SCHEMA public;
		COMMENT ON SCHEMA public IS 'NGS generated';
	END IF;
	SELECT array_to_string(array_agg('DROP VIEW IF EXISTS ' || quote_ident(n.nspname) || '.' || quote_ident(cl.relname) || ' CASCADE;'), '')
	INTO script
	FROM pg_class cl
	INNER JOIN pg_namespace n ON cl.relnamespace = n.oid
	INNER JOIN pg_description d ON d.objoid = cl.oid
	WHERE cl.relkind = 'v' AND d.description LIKE 'NGS volatile%';
	IF length(script) > 0 THEN
		EXECUTE script;
	END IF;
END $$ LANGUAGE plpgsql;

CREATE TABLE IF NOT EXISTS "-NGS-".Database_Migration
(
	Ordinal SERIAL PRIMARY KEY,
	Dsls TEXT,
	Implementations BYTEA,
	Version VARCHAR,
	Applied_At TIMESTAMPTZ DEFAULT (CURRENT_TIMESTAMP)
);

CREATE OR REPLACE FUNCTION "-NGS-".Load_Last_Migration()
RETURNS "-NGS-".Database_Migration AS
$$
SELECT m FROM "-NGS-".Database_Migration m
ORDER BY Ordinal DESC 
LIMIT 1
$$ LANGUAGE sql SECURITY DEFINER STABLE;

CREATE OR REPLACE FUNCTION "-NGS-".Persist_Concepts(dsls TEXT, implementations BYTEA, version VARCHAR)
  RETURNS void AS
$$
BEGIN
	INSERT INTO "-NGS-".Database_Migration(Dsls, Implementations, Version) VALUES(dsls, implementations, version);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION "-NGS-".Generate_Uri2(text, text) RETURNS text AS 
$$
BEGIN
	RETURN replace(replace($1, '\','\\'), '/', '\/')||'/'||replace(replace($2, '\','\\'), '/', '\/');
END;
$$ LANGUAGE PLPGSQL IMMUTABLE;

CREATE OR REPLACE FUNCTION "-NGS-".Generate_Uri3(text, text, text) RETURNS text AS 
$$
BEGIN
	RETURN replace(replace($1, '\','\\'), '/', '\/')||'/'||replace(replace($2, '\','\\'), '/', '\/')||'/'||replace(replace($3, '\','\\'), '/', '\/');
END;
$$ LANGUAGE PLPGSQL IMMUTABLE;

CREATE OR REPLACE FUNCTION "-NGS-".Generate_Uri4(text, text, text, text) RETURNS text AS 
$$
BEGIN
	RETURN replace(replace($1, '\','\\'), '/', '\/')||'/'||replace(replace($2, '\','\\'), '/', '\/')||'/'||replace(replace($3, '\','\\'), '/', '\/')||'/'||replace(replace($4, '\','\\'), '/', '\/');
END;
$$ LANGUAGE PLPGSQL IMMUTABLE;

CREATE OR REPLACE FUNCTION "-NGS-".Generate_Uri5(text, text, text, text, text) RETURNS text AS 
$$
BEGIN
	RETURN replace(replace($1, '\','\\'), '/', '\/')||'/'||replace(replace($2, '\','\\'), '/', '\/')||'/'||replace(replace($3, '\','\\'), '/', '\/')||'/'||replace(replace($4, '\','\\'), '/', '\/')||'/'||replace(replace($5, '\','\\'), '/', '\/');
END;
$$ LANGUAGE PLPGSQL IMMUTABLE;

CREATE OR REPLACE FUNCTION "-NGS-".Generate_Uri(text[]) RETURNS text AS 
$$
BEGIN
	RETURN (SELECT array_to_string(array_agg(replace(replace(u, '\','\\'), '/', '\/')), '/') FROM unnest($1) u);
END;
$$ LANGUAGE PLPGSQL IMMUTABLE;

CREATE OR REPLACE FUNCTION "-NGS-".Safe_Notify(target varchar, name varchar, operation varchar, uris varchar[]) RETURNS VOID AS
$$
DECLARE message VARCHAR;
DECLARE array_size INT;
BEGIN
	array_size = array_upper(uris, 1);
	message = name || ':' || operation || ':' || uris::TEXT;
	IF (array_size > 0 and length(message) < 8000) THEN 
		PERFORM pg_notify(target, message);
	ELSEIF (array_size > 1) THEN
		PERFORM "-NGS-".Safe_Notify(target, name, operation, (SELECT array_agg(uris[i]) FROM generate_series(1, (array_size+1)/2) i));
		PERFORM "-NGS-".Safe_Notify(target, name, operation, (SELECT array_agg(uris[i]) FROM generate_series(array_size/2+1, array_size) i));
	ELSEIF (array_size = 1) THEN
		RAISE EXCEPTION 'uri can''t be longer than 8000 characters';
	END IF;	
END
$$ LANGUAGE PLPGSQL SECURITY DEFINER;

CREATE OR REPLACE FUNCTION "-NGS-".cast_int(int[]) RETURNS TEXT AS
$$ SELECT $1::TEXT[]::TEXT $$ LANGUAGE SQL IMMUTABLE COST 1;
CREATE OR REPLACE FUNCTION "-NGS-".cast_bigint(bigint[]) RETURNS TEXT AS
$$ SELECT $1::TEXT[]::TEXT $$ LANGUAGE SQL IMMUTABLE COST 1;

DO $$ BEGIN
	IF NOT EXISTS (SELECT * FROM pg_cast c JOIN pg_type s ON c.castsource = s.oid JOIN pg_type t ON c.casttarget = t.oid WHERE s.typname = '_int4' AND t.typname = 'text') THEN
		CREATE CAST (int[] AS text) WITH FUNCTION "-NGS-".cast_int(int[]) AS ASSIGNMENT;
	END IF;
END $$ LANGUAGE plpgsql;
DO $$ BEGIN
	IF NOT EXISTS (SELECT * FROM pg_cast c JOIN pg_type s ON c.castsource = s.oid JOIN pg_type t ON c.casttarget = t.oid WHERE s.typname = '_int8' AND t.typname = 'text') THEN
		CREATE CAST (bigint[] AS text) WITH FUNCTION "-NGS-".cast_bigint(bigint[]) AS ASSIGNMENT;
	END IF;
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION "-NGS-".Split_Uri(s text) RETURNS TEXT[] AS
$$
DECLARE i int;
DECLARE pos int;
DECLARE len int;
DECLARE res TEXT[];
DECLARE cur TEXT;
DECLARE c CHAR(1);
BEGIN
	pos = 0;
	i = 1;
	cur = '';
	len = length(s);
	LOOP
		pos = pos + 1;
		EXIT WHEN pos > len;
		c = substr(s, pos, 1);
		IF c = '/' THEN
			res[i] = cur;
			i = i + 1;
			cur = '';
		ELSE
			IF c = '\' THEN
				pos = pos + 1;
				c = substr(s, pos, 1);
			END IF;		
			cur = cur || c;
		END IF;
	END LOOP;
	res[i] = cur;
	return res;
END
$$ LANGUAGE plpgsql SECURITY DEFINER IMMUTABLE;

CREATE OR REPLACE FUNCTION "-NGS-".Load_Type_Info(
	OUT type_schema character varying, 
	OUT type_name character varying, 
	OUT column_name character varying, 
	OUT column_schema character varying,
	OUT column_type character varying, 
	OUT column_index smallint, 
	OUT is_not_null boolean,
	OUT is_ngs_generated boolean)
  RETURNS SETOF record AS
$BODY$
SELECT 
	ns.nspname::varchar, 
	cl.relname::varchar, 
	atr.attname::varchar, 
	ns_ref.nspname::varchar,
	typ.typname::varchar, 
	(SELECT COUNT(*) + 1
	FROM pg_attribute atr_ord
	WHERE 
		atr.attrelid = atr_ord.attrelid
		AND atr_ord.attisdropped = false
		AND atr_ord.attnum > 0
		AND atr_ord.attnum < atr.attnum)::smallint, 
	atr.attnotnull,
	coalesce(d.description LIKE 'NGS generated%', false)
FROM 
	pg_attribute atr
	INNER JOIN pg_class cl ON atr.attrelid = cl.oid
	INNER JOIN pg_namespace ns ON cl.relnamespace = ns.oid
	INNER JOIN pg_type typ ON atr.atttypid = typ.oid
	INNER JOIN pg_namespace ns_ref ON typ.typnamespace = ns_ref.oid
	LEFT JOIN pg_description d ON d.objoid = cl.oid
								AND d.objsubid = atr.attnum
WHERE
	(cl.relkind = 'r' OR cl.relkind = 'v' OR cl.relkind = 'c')
	AND ns.nspname NOT LIKE 'pg_%'
	AND ns.nspname != 'information_schema'
	AND atr.attnum > 0
	AND atr.attisdropped = FALSE
ORDER BY 1, 2, 6
$BODY$
  LANGUAGE SQL STABLE;

CREATE TABLE IF NOT EXISTS "-NGS-".Database_Setting
(
	Key VARCHAR PRIMARY KEY,
	Value TEXT NOT NULL
);

CREATE OR REPLACE FUNCTION "-NGS-".Create_Type_Cast(function VARCHAR, schema VARCHAR, from_name VARCHAR, to_name VARCHAR)
RETURNS void
AS
$$
DECLARE header VARCHAR;
DECLARE source VARCHAR;
DECLARE footer VARCHAR;
DECLARE col_name VARCHAR;
DECLARE type VARCHAR = '"' || schema || '"."' || to_name || '"';
BEGIN
	header = 'CREATE OR REPLACE FUNCTION ' || function || '
RETURNS ' || type || '
AS
$BODY$
SELECT ROW(';
	footer = ')::' || type || '
$BODY$ IMMUTABLE LANGUAGE sql;';
	source = '';
	FOR col_name IN 
		SELECT 
			CASE WHEN 
				EXISTS (SELECT * FROM "-NGS-".Load_Type_Info() f 
					WHERE f.type_schema = schema AND f.type_name = from_name AND f.column_name = t.column_name)
				OR EXISTS(SELECT * FROM pg_proc p JOIN pg_type t_in ON p.proargtypes[0] = t_in.oid 
					JOIN pg_namespace n_in ON t_in.typnamespace = n_in.oid JOIN pg_namespace n ON p.pronamespace = n.oid
					WHERE array_upper(p.proargtypes, 1) = 0 AND n.nspname = 'public' AND t_in.typname = from_name AND p.proname = t.column_name) THEN t.column_name
				ELSE null
			END
		FROM "-NGS-".Load_Type_Info() t
		WHERE 
			t.type_schema = schema 
			AND t.type_name = to_name
		ORDER BY t.column_index 
	LOOP
		IF col_name IS NULL THEN
			source = source || 'null, ';
		ELSE
			source = source || '$1."' || col_name || '", ';
		END IF;
	END LOOP;
	IF (LENGTH(source) > 0) THEN 
		source = SUBSTRING(source, 1, LENGTH(source) - 2);
	END IF;
	EXECUTE (header || source || footer);
END
$$ LANGUAGE plpgsql;;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_extension e WHERE e.extname = 'hstore') THEN	
		CREATE EXTENSION hstore;
		COMMENT ON EXTENSION hstore IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_namespace WHERE nspname = 'Complex') THEN
		CREATE SCHEMA "Complex";
		COMMENT ON SCHEMA "Complex" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_namespace WHERE nspname = 'ComplexObjects') THEN
		CREATE SCHEMA "ComplexObjects";
		COMMENT ON SCHEMA "ComplexObjects" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_namespace WHERE nspname = 'ComplexRelations') THEN
		CREATE SCHEMA "ComplexRelations";
		COMMENT ON SCHEMA "ComplexRelations" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_namespace WHERE nspname = 'Simple') THEN
		CREATE SCHEMA "Simple";
		COMMENT ON SCHEMA "Simple" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_namespace WHERE nspname = 'Standard') THEN
		CREATE SCHEMA "Standard";
		COMMENT ON SCHEMA "Standard" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_namespace WHERE nspname = 'StandardObjects') THEN
		CREATE SCHEMA "StandardObjects";
		COMMENT ON SCHEMA "StandardObjects" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_namespace WHERE nspname = 'StandardRelations') THEN
		CREATE SCHEMA "StandardRelations";
		COMMENT ON SCHEMA "StandardRelations" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'Complex' AND t.typname = 'Currency') THEN	
		CREATE TYPE "Complex"."Currency" AS ENUM ('EUR', 'USD', 'Other');
		COMMENT ON TYPE "Complex"."Currency" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'Complex' AND t.typname = 'BankScrape') THEN	
		CREATE TYPE "Complex"."BankScrape" AS ();
		COMMENT ON TYPE "Complex"."BankScrape" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'Complex' AND t.typname = '-ngs_BankScrape_type-') THEN	
		CREATE TYPE "Complex"."-ngs_BankScrape_type-" AS ();
		COMMENT ON TYPE "Complex"."-ngs_BankScrape_type-" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'ComplexObjects' AND t.typname = '-ngs_BankScrape_type-') THEN	
		CREATE TYPE "ComplexObjects"."-ngs_BankScrape_type-" AS ();
		COMMENT ON TYPE "ComplexObjects"."-ngs_BankScrape_type-" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'ComplexObjects' AND c.relname = 'BankScrape') THEN	
		CREATE TABLE "ComplexObjects"."BankScrape" ();
		COMMENT ON TABLE "ComplexObjects"."BankScrape" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'ComplexObjects' AND c.relname = 'BankScrape_sequence') THEN
		CREATE SEQUENCE "ComplexObjects"."BankScrape_sequence";
		COMMENT ON SEQUENCE "ComplexObjects"."BankScrape_sequence" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'ComplexObjects' AND t.typname = '-ngs_Account_type-') THEN	
		CREATE TYPE "ComplexObjects"."-ngs_Account_type-" AS ();
		COMMENT ON TYPE "ComplexObjects"."-ngs_Account_type-" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'ComplexObjects' AND t.typname = 'Account') THEN	
		CREATE TYPE "ComplexObjects"."Account" AS ();
		COMMENT ON TYPE "ComplexObjects"."Account" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'ComplexObjects' AND t.typname = '-ngs_Transaction_type-') THEN	
		CREATE TYPE "ComplexObjects"."-ngs_Transaction_type-" AS ();
		COMMENT ON TYPE "ComplexObjects"."-ngs_Transaction_type-" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'ComplexObjects' AND t.typname = 'Transaction') THEN	
		CREATE TYPE "ComplexObjects"."Transaction" AS ();
		COMMENT ON TYPE "ComplexObjects"."Transaction" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'ComplexRelations' AND t.typname = '-ngs_BankScrape_type-') THEN	
		CREATE TYPE "ComplexRelations"."-ngs_BankScrape_type-" AS ();
		COMMENT ON TYPE "ComplexRelations"."-ngs_BankScrape_type-" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'ComplexRelations' AND c.relname = 'BankScrape') THEN	
		CREATE TABLE "ComplexRelations"."BankScrape" ();
		COMMENT ON TABLE "ComplexRelations"."BankScrape" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'ComplexRelations' AND c.relname = 'BankScrape_sequence') THEN
		CREATE SEQUENCE "ComplexRelations"."BankScrape_sequence";
		COMMENT ON SEQUENCE "ComplexRelations"."BankScrape_sequence" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'ComplexRelations' AND t.typname = '-ngs_Account_type-') THEN	
		CREATE TYPE "ComplexRelations"."-ngs_Account_type-" AS ();
		COMMENT ON TYPE "ComplexRelations"."-ngs_Account_type-" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'ComplexRelations' AND c.relname = 'Account') THEN	
		CREATE TABLE "ComplexRelations"."Account" ();
		COMMENT ON TABLE "ComplexRelations"."Account" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'ComplexRelations' AND t.typname = '-ngs_Transaction_type-') THEN	
		CREATE TYPE "ComplexRelations"."-ngs_Transaction_type-" AS ();
		COMMENT ON TYPE "ComplexRelations"."-ngs_Transaction_type-" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'ComplexRelations' AND c.relname = 'Transaction') THEN	
		CREATE TABLE "ComplexRelations"."Transaction" ();
		COMMENT ON TABLE "ComplexRelations"."Transaction" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'Simple' AND t.typname = '-ngs_Post_type-') THEN	
		CREATE TYPE "Simple"."-ngs_Post_type-" AS ();
		COMMENT ON TYPE "Simple"."-ngs_Post_type-" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'Simple' AND c.relname = 'Post') THEN	
		CREATE TABLE "Simple"."Post" ();
		COMMENT ON TABLE "Simple"."Post" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'Simple' AND c.relname = 'Post_sequence') THEN
		CREATE SEQUENCE "Simple"."Post_sequence";
		COMMENT ON SEQUENCE "Simple"."Post_sequence" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'Standard' AND t.typname = 'Invoice') THEN	
		CREATE TYPE "Standard"."Invoice" AS ();
		COMMENT ON TYPE "Standard"."Invoice" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'Standard' AND t.typname = '-ngs_Invoice_type-') THEN	
		CREATE TYPE "Standard"."-ngs_Invoice_type-" AS ();
		COMMENT ON TYPE "Standard"."-ngs_Invoice_type-" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'StandardObjects' AND t.typname = '-ngs_Invoice_type-') THEN	
		CREATE TYPE "StandardObjects"."-ngs_Invoice_type-" AS ();
		COMMENT ON TYPE "StandardObjects"."-ngs_Invoice_type-" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'StandardObjects' AND c.relname = 'Invoice') THEN	
		CREATE TABLE "StandardObjects"."Invoice" ();
		COMMENT ON TABLE "StandardObjects"."Invoice" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'StandardObjects' AND c.relname = 'Invoice_sequence') THEN
		CREATE SEQUENCE "StandardObjects"."Invoice_sequence";
		COMMENT ON SEQUENCE "StandardObjects"."Invoice_sequence" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'StandardObjects' AND t.typname = '-ngs_Item_type-') THEN	
		CREATE TYPE "StandardObjects"."-ngs_Item_type-" AS ();
		COMMENT ON TYPE "StandardObjects"."-ngs_Item_type-" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'StandardObjects' AND t.typname = 'Item') THEN	
		CREATE TYPE "StandardObjects"."Item" AS ();
		COMMENT ON TYPE "StandardObjects"."Item" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'StandardRelations' AND t.typname = '-ngs_Invoice_type-') THEN	
		CREATE TYPE "StandardRelations"."-ngs_Invoice_type-" AS ();
		COMMENT ON TYPE "StandardRelations"."-ngs_Invoice_type-" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'StandardRelations' AND c.relname = 'Invoice') THEN	
		CREATE TABLE "StandardRelations"."Invoice" ();
		COMMENT ON TABLE "StandardRelations"."Invoice" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'StandardRelations' AND c.relname = 'Invoice_sequence') THEN
		CREATE SEQUENCE "StandardRelations"."Invoice_sequence";
		COMMENT ON SEQUENCE "StandardRelations"."Invoice_sequence" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'StandardRelations' AND t.typname = '-ngs_Item_type-') THEN	
		CREATE TYPE "StandardRelations"."-ngs_Item_type-" AS ();
		COMMENT ON TYPE "StandardRelations"."-ngs_Item_type-" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'StandardRelations' AND c.relname = 'Item') THEN	
		CREATE TABLE "StandardRelations"."Item" ();
		COMMENT ON TABLE "StandardRelations"."Item" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ 
BEGIN
	IF NOT EXISTS(SELECT * FROM pg_enum e JOIN pg_type t ON e.enumtypid = t.oid JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'Complex' AND t.typname = 'Currency' AND e.enumlabel = 'EUR') THEN
		--ALTER TYPE "Complex"."Currency" ADD VALUE IF NOT EXISTS 'EUR'; -- this doesn't work inside a transaction ;( use a hack to add new values...
		--TODO: detect OID wraparounds and throw an exception in that case
		INSERT INTO pg_enum(enumtypid, enumlabel, enumsortorder)
		SELECT t.oid, 'EUR', (SELECT MAX(enumsortorder) + 1 FROM pg_enum e WHERE e.enumtypid = t.oid)
		FROM pg_type t 
		INNER JOIN pg_namespace n ON n.oid = t.typnamespace 
		WHERE n.nspname = 'Complex' AND t.typname = 'Currency';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ 
BEGIN
	IF NOT EXISTS(SELECT * FROM pg_enum e JOIN pg_type t ON e.enumtypid = t.oid JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'Complex' AND t.typname = 'Currency' AND e.enumlabel = 'USD') THEN
		--ALTER TYPE "Complex"."Currency" ADD VALUE IF NOT EXISTS 'USD'; -- this doesn't work inside a transaction ;( use a hack to add new values...
		--TODO: detect OID wraparounds and throw an exception in that case
		INSERT INTO pg_enum(enumtypid, enumlabel, enumsortorder)
		SELECT t.oid, 'USD', (SELECT MAX(enumsortorder) + 1 FROM pg_enum e WHERE e.enumtypid = t.oid)
		FROM pg_type t 
		INNER JOIN pg_namespace n ON n.oid = t.typnamespace 
		WHERE n.nspname = 'Complex' AND t.typname = 'Currency';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ 
BEGIN
	IF NOT EXISTS(SELECT * FROM pg_enum e JOIN pg_type t ON e.enumtypid = t.oid JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'Complex' AND t.typname = 'Currency' AND e.enumlabel = 'Other') THEN
		--ALTER TYPE "Complex"."Currency" ADD VALUE IF NOT EXISTS 'Other'; -- this doesn't work inside a transaction ;( use a hack to add new values...
		--TODO: detect OID wraparounds and throw an exception in that case
		INSERT INTO pg_enum(enumtypid, enumlabel, enumsortorder)
		SELECT t.oid, 'Other', (SELECT MAX(enumsortorder) + 1 FROM pg_enum e WHERE e.enumtypid = t.oid)
		FROM pg_type t 
		INNER JOIN pg_namespace n ON n.oid = t.typnamespace 
		WHERE n.nspname = 'Complex' AND t.typname = 'Currency';
	END IF;
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION "Complex"."cast_BankScrape_to_type"("Complex"."BankScrape") RETURNS "Complex"."-ngs_BankScrape_type-" AS $$ SELECT $1::text::"Complex"."-ngs_BankScrape_type-" $$ IMMUTABLE LANGUAGE sql COST 1;
CREATE OR REPLACE FUNCTION "Complex"."cast_BankScrape_to_type"("Complex"."-ngs_BankScrape_type-") RETURNS "Complex"."BankScrape" AS $$ SELECT $1::text::"Complex"."BankScrape" $$ IMMUTABLE LANGUAGE sql COST 1;
CREATE OR REPLACE FUNCTION cast_to_text("Complex"."BankScrape") RETURNS text AS $$ SELECT $1::VARCHAR $$ IMMUTABLE LANGUAGE sql COST 1;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_cast c JOIN pg_type s ON c.castsource = s.oid JOIN pg_type t ON c.casttarget = t.oid JOIN pg_namespace n ON n.oid = s.typnamespace AND n.oid = t.typnamespace
					WHERE n.nspname = 'Complex' AND s.typname = 'BankScrape' AND t.typname = '-ngs_BankScrape_type-') THEN
		CREATE CAST ("Complex"."-ngs_BankScrape_type-" AS "Complex"."BankScrape") WITH FUNCTION "Complex"."cast_BankScrape_to_type"("Complex"."-ngs_BankScrape_type-") AS IMPLICIT;
		CREATE CAST ("Complex"."BankScrape" AS "Complex"."-ngs_BankScrape_type-") WITH FUNCTION "Complex"."cast_BankScrape_to_type"("Complex"."BankScrape") AS IMPLICIT;
		CREATE CAST ("Complex"."BankScrape" AS text) WITH FUNCTION cast_to_text("Complex"."BankScrape") AS ASSIGNMENT;
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'Complex' AND type_name = '-ngs_BankScrape_type-' AND column_name = 'website') THEN
		ALTER TYPE "Complex"."-ngs_BankScrape_type-" ADD ATTRIBUTE "website" VARCHAR;
		COMMENT ON COLUMN "Complex"."-ngs_BankScrape_type-"."website" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'Complex' AND type_name = 'BankScrape' AND column_name = 'website') THEN
		ALTER TYPE "Complex"."BankScrape" ADD ATTRIBUTE "website" VARCHAR;
		COMMENT ON COLUMN "Complex"."BankScrape"."website" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'Complex' AND type_name = '-ngs_BankScrape_type-' AND column_name = 'at') THEN
		ALTER TYPE "Complex"."-ngs_BankScrape_type-" ADD ATTRIBUTE "at" TIMESTAMPTZ;
		COMMENT ON COLUMN "Complex"."-ngs_BankScrape_type-"."at" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'Complex' AND type_name = 'BankScrape' AND column_name = 'at') THEN
		ALTER TYPE "Complex"."BankScrape" ADD ATTRIBUTE "at" TIMESTAMPTZ;
		COMMENT ON COLUMN "Complex"."BankScrape"."at" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'Complex' AND type_name = '-ngs_BankScrape_type-' AND column_name = 'info') THEN
		ALTER TYPE "Complex"."-ngs_BankScrape_type-" ADD ATTRIBUTE "info" HSTORE;
		COMMENT ON COLUMN "Complex"."-ngs_BankScrape_type-"."info" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'Complex' AND type_name = 'BankScrape' AND column_name = 'info') THEN
		ALTER TYPE "Complex"."BankScrape" ADD ATTRIBUTE "info" HSTORE;
		COMMENT ON COLUMN "Complex"."BankScrape"."info" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'Complex' AND type_name = '-ngs_BankScrape_type-' AND column_name = 'externalId') THEN
		ALTER TYPE "Complex"."-ngs_BankScrape_type-" ADD ATTRIBUTE "externalId" VARCHAR(50);
		COMMENT ON COLUMN "Complex"."-ngs_BankScrape_type-"."externalId" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'Complex' AND type_name = 'BankScrape' AND column_name = 'externalId') THEN
		ALTER TYPE "Complex"."BankScrape" ADD ATTRIBUTE "externalId" VARCHAR(50);
		COMMENT ON COLUMN "Complex"."BankScrape"."externalId" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'Complex' AND type_name = '-ngs_BankScrape_type-' AND column_name = 'ranking') THEN
		ALTER TYPE "Complex"."-ngs_BankScrape_type-" ADD ATTRIBUTE "ranking" INT;
		COMMENT ON COLUMN "Complex"."-ngs_BankScrape_type-"."ranking" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'Complex' AND type_name = 'BankScrape' AND column_name = 'ranking') THEN
		ALTER TYPE "Complex"."BankScrape" ADD ATTRIBUTE "ranking" INT;
		COMMENT ON COLUMN "Complex"."BankScrape"."ranking" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'Complex' AND type_name = '-ngs_BankScrape_type-' AND column_name = 'tags') THEN
		ALTER TYPE "Complex"."-ngs_BankScrape_type-" ADD ATTRIBUTE "tags" VARCHAR(10)[];
		COMMENT ON COLUMN "Complex"."-ngs_BankScrape_type-"."tags" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'Complex' AND type_name = 'BankScrape' AND column_name = 'tags') THEN
		ALTER TYPE "Complex"."BankScrape" ADD ATTRIBUTE "tags" VARCHAR(10)[];
		COMMENT ON COLUMN "Complex"."BankScrape"."tags" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'Complex' AND type_name = '-ngs_BankScrape_type-' AND column_name = 'createdAt') THEN
		ALTER TYPE "Complex"."-ngs_BankScrape_type-" ADD ATTRIBUTE "createdAt" TIMESTAMPTZ;
		COMMENT ON COLUMN "Complex"."-ngs_BankScrape_type-"."createdAt" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'Complex' AND type_name = 'BankScrape' AND column_name = 'createdAt') THEN
		ALTER TYPE "Complex"."BankScrape" ADD ATTRIBUTE "createdAt" TIMESTAMPTZ;
		COMMENT ON COLUMN "Complex"."BankScrape"."createdAt" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexObjects' AND type_name = '-ngs_BankScrape_type-' AND column_name = 'id') THEN
		ALTER TYPE "ComplexObjects"."-ngs_BankScrape_type-" ADD ATTRIBUTE "id" INT;
		COMMENT ON COLUMN "ComplexObjects"."-ngs_BankScrape_type-"."id" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexObjects' AND type_name = 'BankScrape' AND column_name = 'id') THEN
		ALTER TABLE "ComplexObjects"."BankScrape" ADD COLUMN "id" INT;
		COMMENT ON COLUMN "ComplexObjects"."BankScrape"."id" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexObjects' AND type_name = '-ngs_BankScrape_type-' AND column_name = 'accounts') THEN
		ALTER TYPE "ComplexObjects"."-ngs_BankScrape_type-" ADD ATTRIBUTE "accounts" "ComplexObjects"."-ngs_Account_type-"[];
		COMMENT ON COLUMN "ComplexObjects"."-ngs_BankScrape_type-"."accounts" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexObjects' AND type_name = 'BankScrape' AND column_name = 'accounts') THEN
		ALTER TABLE "ComplexObjects"."BankScrape" ADD COLUMN "accounts" "ComplexObjects"."Account"[];
		COMMENT ON COLUMN "ComplexObjects"."BankScrape"."accounts" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION "ComplexObjects"."cast_Account_to_type"("ComplexObjects"."Account") RETURNS "ComplexObjects"."-ngs_Account_type-" AS $$ SELECT $1::text::"ComplexObjects"."-ngs_Account_type-" $$ IMMUTABLE LANGUAGE sql COST 1;
CREATE OR REPLACE FUNCTION "ComplexObjects"."cast_Account_to_type"("ComplexObjects"."-ngs_Account_type-") RETURNS "ComplexObjects"."Account" AS $$ SELECT $1::text::"ComplexObjects"."Account" $$ IMMUTABLE LANGUAGE sql COST 1;
CREATE OR REPLACE FUNCTION cast_to_text("ComplexObjects"."Account") RETURNS text AS $$ SELECT $1::VARCHAR $$ IMMUTABLE LANGUAGE sql COST 1;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_cast c JOIN pg_type s ON c.castsource = s.oid JOIN pg_type t ON c.casttarget = t.oid JOIN pg_namespace n ON n.oid = s.typnamespace AND n.oid = t.typnamespace
					WHERE n.nspname = 'ComplexObjects' AND s.typname = 'Account' AND t.typname = '-ngs_Account_type-') THEN
		CREATE CAST ("ComplexObjects"."-ngs_Account_type-" AS "ComplexObjects"."Account") WITH FUNCTION "ComplexObjects"."cast_Account_to_type"("ComplexObjects"."-ngs_Account_type-") AS IMPLICIT;
		CREATE CAST ("ComplexObjects"."Account" AS "ComplexObjects"."-ngs_Account_type-") WITH FUNCTION "ComplexObjects"."cast_Account_to_type"("ComplexObjects"."Account") AS IMPLICIT;
		CREATE CAST ("ComplexObjects"."Account" AS text) WITH FUNCTION cast_to_text("ComplexObjects"."Account") AS ASSIGNMENT;
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexObjects' AND type_name = '-ngs_Account_type-' AND column_name = 'balance') THEN
		ALTER TYPE "ComplexObjects"."-ngs_Account_type-" ADD ATTRIBUTE "balance" NUMERIC(22,2);
		COMMENT ON COLUMN "ComplexObjects"."-ngs_Account_type-"."balance" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexObjects' AND type_name = 'Account' AND column_name = 'balance') THEN
		ALTER TYPE "ComplexObjects"."Account" ADD ATTRIBUTE "balance" NUMERIC(22,2);
		COMMENT ON COLUMN "ComplexObjects"."Account"."balance" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexObjects' AND type_name = '-ngs_Account_type-' AND column_name = 'number') THEN
		ALTER TYPE "ComplexObjects"."-ngs_Account_type-" ADD ATTRIBUTE "number" VARCHAR(40);
		COMMENT ON COLUMN "ComplexObjects"."-ngs_Account_type-"."number" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexObjects' AND type_name = 'Account' AND column_name = 'number') THEN
		ALTER TYPE "ComplexObjects"."Account" ADD ATTRIBUTE "number" VARCHAR(40);
		COMMENT ON COLUMN "ComplexObjects"."Account"."number" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexObjects' AND type_name = '-ngs_Account_type-' AND column_name = 'name') THEN
		ALTER TYPE "ComplexObjects"."-ngs_Account_type-" ADD ATTRIBUTE "name" VARCHAR(100);
		COMMENT ON COLUMN "ComplexObjects"."-ngs_Account_type-"."name" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexObjects' AND type_name = 'Account' AND column_name = 'name') THEN
		ALTER TYPE "ComplexObjects"."Account" ADD ATTRIBUTE "name" VARCHAR(100);
		COMMENT ON COLUMN "ComplexObjects"."Account"."name" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexObjects' AND type_name = '-ngs_Account_type-' AND column_name = 'notes') THEN
		ALTER TYPE "ComplexObjects"."-ngs_Account_type-" ADD ATTRIBUTE "notes" VARCHAR(800);
		COMMENT ON COLUMN "ComplexObjects"."-ngs_Account_type-"."notes" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexObjects' AND type_name = 'Account' AND column_name = 'notes') THEN
		ALTER TYPE "ComplexObjects"."Account" ADD ATTRIBUTE "notes" VARCHAR(800);
		COMMENT ON COLUMN "ComplexObjects"."Account"."notes" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexObjects' AND type_name = '-ngs_Account_type-' AND column_name = 'transactions') THEN
		ALTER TYPE "ComplexObjects"."-ngs_Account_type-" ADD ATTRIBUTE "transactions" "ComplexObjects"."-ngs_Transaction_type-"[];
		COMMENT ON COLUMN "ComplexObjects"."-ngs_Account_type-"."transactions" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexObjects' AND type_name = 'Account' AND column_name = 'transactions') THEN
		ALTER TYPE "ComplexObjects"."Account" ADD ATTRIBUTE "transactions" "ComplexObjects"."Transaction"[];
		COMMENT ON COLUMN "ComplexObjects"."Account"."transactions" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION "ComplexObjects"."cast_Transaction_to_type"("ComplexObjects"."Transaction") RETURNS "ComplexObjects"."-ngs_Transaction_type-" AS $$ SELECT $1::text::"ComplexObjects"."-ngs_Transaction_type-" $$ IMMUTABLE LANGUAGE sql COST 1;
CREATE OR REPLACE FUNCTION "ComplexObjects"."cast_Transaction_to_type"("ComplexObjects"."-ngs_Transaction_type-") RETURNS "ComplexObjects"."Transaction" AS $$ SELECT $1::text::"ComplexObjects"."Transaction" $$ IMMUTABLE LANGUAGE sql COST 1;
CREATE OR REPLACE FUNCTION cast_to_text("ComplexObjects"."Transaction") RETURNS text AS $$ SELECT $1::VARCHAR $$ IMMUTABLE LANGUAGE sql COST 1;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_cast c JOIN pg_type s ON c.castsource = s.oid JOIN pg_type t ON c.casttarget = t.oid JOIN pg_namespace n ON n.oid = s.typnamespace AND n.oid = t.typnamespace
					WHERE n.nspname = 'ComplexObjects' AND s.typname = 'Transaction' AND t.typname = '-ngs_Transaction_type-') THEN
		CREATE CAST ("ComplexObjects"."-ngs_Transaction_type-" AS "ComplexObjects"."Transaction") WITH FUNCTION "ComplexObjects"."cast_Transaction_to_type"("ComplexObjects"."-ngs_Transaction_type-") AS IMPLICIT;
		CREATE CAST ("ComplexObjects"."Transaction" AS "ComplexObjects"."-ngs_Transaction_type-") WITH FUNCTION "ComplexObjects"."cast_Transaction_to_type"("ComplexObjects"."Transaction") AS IMPLICIT;
		CREATE CAST ("ComplexObjects"."Transaction" AS text) WITH FUNCTION cast_to_text("ComplexObjects"."Transaction") AS ASSIGNMENT;
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexObjects' AND type_name = '-ngs_Transaction_type-' AND column_name = 'date') THEN
		ALTER TYPE "ComplexObjects"."-ngs_Transaction_type-" ADD ATTRIBUTE "date" DATE;
		COMMENT ON COLUMN "ComplexObjects"."-ngs_Transaction_type-"."date" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexObjects' AND type_name = 'Transaction' AND column_name = 'date') THEN
		ALTER TYPE "ComplexObjects"."Transaction" ADD ATTRIBUTE "date" DATE;
		COMMENT ON COLUMN "ComplexObjects"."Transaction"."date" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexObjects' AND type_name = '-ngs_Transaction_type-' AND column_name = 'description') THEN
		ALTER TYPE "ComplexObjects"."-ngs_Transaction_type-" ADD ATTRIBUTE "description" VARCHAR(200);
		COMMENT ON COLUMN "ComplexObjects"."-ngs_Transaction_type-"."description" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexObjects' AND type_name = 'Transaction' AND column_name = 'description') THEN
		ALTER TYPE "ComplexObjects"."Transaction" ADD ATTRIBUTE "description" VARCHAR(200);
		COMMENT ON COLUMN "ComplexObjects"."Transaction"."description" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexObjects' AND type_name = '-ngs_Transaction_type-' AND column_name = 'currency') THEN
		ALTER TYPE "ComplexObjects"."-ngs_Transaction_type-" ADD ATTRIBUTE "currency" "Complex"."Currency";
		COMMENT ON COLUMN "ComplexObjects"."-ngs_Transaction_type-"."currency" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexObjects' AND type_name = 'Transaction' AND column_name = 'currency') THEN
		ALTER TYPE "ComplexObjects"."Transaction" ADD ATTRIBUTE "currency" "Complex"."Currency";
		COMMENT ON COLUMN "ComplexObjects"."Transaction"."currency" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexObjects' AND type_name = '-ngs_Transaction_type-' AND column_name = 'amount') THEN
		ALTER TYPE "ComplexObjects"."-ngs_Transaction_type-" ADD ATTRIBUTE "amount" NUMERIC(22,2);
		COMMENT ON COLUMN "ComplexObjects"."-ngs_Transaction_type-"."amount" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexObjects' AND type_name = 'Transaction' AND column_name = 'amount') THEN
		ALTER TYPE "ComplexObjects"."Transaction" ADD ATTRIBUTE "amount" NUMERIC(22,2);
		COMMENT ON COLUMN "ComplexObjects"."Transaction"."amount" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = '-ngs_BankScrape_type-' AND column_name = 'id') THEN
		ALTER TYPE "ComplexRelations"."-ngs_BankScrape_type-" ADD ATTRIBUTE "id" INT;
		COMMENT ON COLUMN "ComplexRelations"."-ngs_BankScrape_type-"."id" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = 'BankScrape' AND column_name = 'id') THEN
		ALTER TABLE "ComplexRelations"."BankScrape" ADD COLUMN "id" INT;
		COMMENT ON COLUMN "ComplexRelations"."BankScrape"."id" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = '-ngs_BankScrape_type-' AND column_name = 'accountsURI') THEN
		ALTER TYPE "ComplexRelations"."-ngs_BankScrape_type-" ADD ATTRIBUTE "accountsURI" VARCHAR[];
		COMMENT ON COLUMN "ComplexRelations"."-ngs_BankScrape_type-"."accountsURI" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = '-ngs_Account_type-' AND column_name = 'balance') THEN
		ALTER TYPE "ComplexRelations"."-ngs_Account_type-" ADD ATTRIBUTE "balance" NUMERIC(22,2);
		COMMENT ON COLUMN "ComplexRelations"."-ngs_Account_type-"."balance" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = 'Account' AND column_name = 'balance') THEN
		ALTER TABLE "ComplexRelations"."Account" ADD COLUMN "balance" NUMERIC(22,2);
		COMMENT ON COLUMN "ComplexRelations"."Account"."balance" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = '-ngs_Account_type-' AND column_name = 'number') THEN
		ALTER TYPE "ComplexRelations"."-ngs_Account_type-" ADD ATTRIBUTE "number" VARCHAR(40);
		COMMENT ON COLUMN "ComplexRelations"."-ngs_Account_type-"."number" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = 'Account' AND column_name = 'number') THEN
		ALTER TABLE "ComplexRelations"."Account" ADD COLUMN "number" VARCHAR(40);
		COMMENT ON COLUMN "ComplexRelations"."Account"."number" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = '-ngs_Account_type-' AND column_name = 'name') THEN
		ALTER TYPE "ComplexRelations"."-ngs_Account_type-" ADD ATTRIBUTE "name" VARCHAR(100);
		COMMENT ON COLUMN "ComplexRelations"."-ngs_Account_type-"."name" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = 'Account' AND column_name = 'name') THEN
		ALTER TABLE "ComplexRelations"."Account" ADD COLUMN "name" VARCHAR(100);
		COMMENT ON COLUMN "ComplexRelations"."Account"."name" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = '-ngs_Account_type-' AND column_name = 'notes') THEN
		ALTER TYPE "ComplexRelations"."-ngs_Account_type-" ADD ATTRIBUTE "notes" VARCHAR(800);
		COMMENT ON COLUMN "ComplexRelations"."-ngs_Account_type-"."notes" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = 'Account' AND column_name = 'notes') THEN
		ALTER TABLE "ComplexRelations"."Account" ADD COLUMN "notes" VARCHAR(800);
		COMMENT ON COLUMN "ComplexRelations"."Account"."notes" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = '-ngs_Account_type-' AND column_name = 'transactionsURI') THEN
		ALTER TYPE "ComplexRelations"."-ngs_Account_type-" ADD ATTRIBUTE "transactionsURI" VARCHAR[];
		COMMENT ON COLUMN "ComplexRelations"."-ngs_Account_type-"."transactionsURI" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = '-ngs_Transaction_type-' AND column_name = 'date') THEN
		ALTER TYPE "ComplexRelations"."-ngs_Transaction_type-" ADD ATTRIBUTE "date" DATE;
		COMMENT ON COLUMN "ComplexRelations"."-ngs_Transaction_type-"."date" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = 'Transaction' AND column_name = 'date') THEN
		ALTER TABLE "ComplexRelations"."Transaction" ADD COLUMN "date" DATE;
		COMMENT ON COLUMN "ComplexRelations"."Transaction"."date" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = '-ngs_Transaction_type-' AND column_name = 'description') THEN
		ALTER TYPE "ComplexRelations"."-ngs_Transaction_type-" ADD ATTRIBUTE "description" VARCHAR(200);
		COMMENT ON COLUMN "ComplexRelations"."-ngs_Transaction_type-"."description" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = 'Transaction' AND column_name = 'description') THEN
		ALTER TABLE "ComplexRelations"."Transaction" ADD COLUMN "description" VARCHAR(200);
		COMMENT ON COLUMN "ComplexRelations"."Transaction"."description" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = '-ngs_Transaction_type-' AND column_name = 'currency') THEN
		ALTER TYPE "ComplexRelations"."-ngs_Transaction_type-" ADD ATTRIBUTE "currency" "Complex"."Currency";
		COMMENT ON COLUMN "ComplexRelations"."-ngs_Transaction_type-"."currency" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = 'Transaction' AND column_name = 'currency') THEN
		ALTER TABLE "ComplexRelations"."Transaction" ADD COLUMN "currency" "Complex"."Currency";
		COMMENT ON COLUMN "ComplexRelations"."Transaction"."currency" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = '-ngs_Transaction_type-' AND column_name = 'amount') THEN
		ALTER TYPE "ComplexRelations"."-ngs_Transaction_type-" ADD ATTRIBUTE "amount" NUMERIC(22,2);
		COMMENT ON COLUMN "ComplexRelations"."-ngs_Transaction_type-"."amount" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = 'Transaction' AND column_name = 'amount') THEN
		ALTER TABLE "ComplexRelations"."Transaction" ADD COLUMN "amount" NUMERIC(22,2);
		COMMENT ON COLUMN "ComplexRelations"."Transaction"."amount" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'Simple' AND type_name = '-ngs_Post_type-' AND column_name = 'id') THEN
		ALTER TYPE "Simple"."-ngs_Post_type-" ADD ATTRIBUTE "id" UUID;
		COMMENT ON COLUMN "Simple"."-ngs_Post_type-"."id" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'Simple' AND type_name = 'Post' AND column_name = 'id') THEN
		ALTER TABLE "Simple"."Post" ADD COLUMN "id" UUID;
		COMMENT ON COLUMN "Simple"."Post"."id" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'Simple' AND type_name = '-ngs_Post_type-' AND column_name = 'title') THEN
		ALTER TYPE "Simple"."-ngs_Post_type-" ADD ATTRIBUTE "title" VARCHAR;
		COMMENT ON COLUMN "Simple"."-ngs_Post_type-"."title" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'Simple' AND type_name = 'Post' AND column_name = 'title') THEN
		ALTER TABLE "Simple"."Post" ADD COLUMN "title" VARCHAR;
		COMMENT ON COLUMN "Simple"."Post"."title" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'Simple' AND type_name = '-ngs_Post_type-' AND column_name = 'created') THEN
		ALTER TYPE "Simple"."-ngs_Post_type-" ADD ATTRIBUTE "created" DATE;
		COMMENT ON COLUMN "Simple"."-ngs_Post_type-"."created" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'Simple' AND type_name = 'Post' AND column_name = 'created') THEN
		ALTER TABLE "Simple"."Post" ADD COLUMN "created" DATE;
		COMMENT ON COLUMN "Simple"."Post"."created" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION "Standard"."cast_Invoice_to_type"("Standard"."Invoice") RETURNS "Standard"."-ngs_Invoice_type-" AS $$ SELECT $1::text::"Standard"."-ngs_Invoice_type-" $$ IMMUTABLE LANGUAGE sql COST 1;
CREATE OR REPLACE FUNCTION "Standard"."cast_Invoice_to_type"("Standard"."-ngs_Invoice_type-") RETURNS "Standard"."Invoice" AS $$ SELECT $1::text::"Standard"."Invoice" $$ IMMUTABLE LANGUAGE sql COST 1;
CREATE OR REPLACE FUNCTION cast_to_text("Standard"."Invoice") RETURNS text AS $$ SELECT $1::VARCHAR $$ IMMUTABLE LANGUAGE sql COST 1;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_cast c JOIN pg_type s ON c.castsource = s.oid JOIN pg_type t ON c.casttarget = t.oid JOIN pg_namespace n ON n.oid = s.typnamespace AND n.oid = t.typnamespace
					WHERE n.nspname = 'Standard' AND s.typname = 'Invoice' AND t.typname = '-ngs_Invoice_type-') THEN
		CREATE CAST ("Standard"."-ngs_Invoice_type-" AS "Standard"."Invoice") WITH FUNCTION "Standard"."cast_Invoice_to_type"("Standard"."-ngs_Invoice_type-") AS IMPLICIT;
		CREATE CAST ("Standard"."Invoice" AS "Standard"."-ngs_Invoice_type-") WITH FUNCTION "Standard"."cast_Invoice_to_type"("Standard"."Invoice") AS IMPLICIT;
		CREATE CAST ("Standard"."Invoice" AS text) WITH FUNCTION cast_to_text("Standard"."Invoice") AS ASSIGNMENT;
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'Standard' AND type_name = '-ngs_Invoice_type-' AND column_name = 'dueDate') THEN
		ALTER TYPE "Standard"."-ngs_Invoice_type-" ADD ATTRIBUTE "dueDate" DATE;
		COMMENT ON COLUMN "Standard"."-ngs_Invoice_type-"."dueDate" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'Standard' AND type_name = 'Invoice' AND column_name = 'dueDate') THEN
		ALTER TYPE "Standard"."Invoice" ADD ATTRIBUTE "dueDate" DATE;
		COMMENT ON COLUMN "Standard"."Invoice"."dueDate" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'Standard' AND type_name = '-ngs_Invoice_type-' AND column_name = 'total') THEN
		ALTER TYPE "Standard"."-ngs_Invoice_type-" ADD ATTRIBUTE "total" NUMERIC;
		COMMENT ON COLUMN "Standard"."-ngs_Invoice_type-"."total" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'Standard' AND type_name = 'Invoice' AND column_name = 'total') THEN
		ALTER TYPE "Standard"."Invoice" ADD ATTRIBUTE "total" NUMERIC;
		COMMENT ON COLUMN "Standard"."Invoice"."total" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'Standard' AND type_name = '-ngs_Invoice_type-' AND column_name = 'paid') THEN
		ALTER TYPE "Standard"."-ngs_Invoice_type-" ADD ATTRIBUTE "paid" TIMESTAMPTZ;
		COMMENT ON COLUMN "Standard"."-ngs_Invoice_type-"."paid" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'Standard' AND type_name = 'Invoice' AND column_name = 'paid') THEN
		ALTER TYPE "Standard"."Invoice" ADD ATTRIBUTE "paid" TIMESTAMPTZ;
		COMMENT ON COLUMN "Standard"."Invoice"."paid" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'Standard' AND type_name = '-ngs_Invoice_type-' AND column_name = 'canceled') THEN
		ALTER TYPE "Standard"."-ngs_Invoice_type-" ADD ATTRIBUTE "canceled" BOOL;
		COMMENT ON COLUMN "Standard"."-ngs_Invoice_type-"."canceled" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'Standard' AND type_name = 'Invoice' AND column_name = 'canceled') THEN
		ALTER TYPE "Standard"."Invoice" ADD ATTRIBUTE "canceled" BOOL;
		COMMENT ON COLUMN "Standard"."Invoice"."canceled" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'Standard' AND type_name = '-ngs_Invoice_type-' AND column_name = 'version') THEN
		ALTER TYPE "Standard"."-ngs_Invoice_type-" ADD ATTRIBUTE "version" BIGINT;
		COMMENT ON COLUMN "Standard"."-ngs_Invoice_type-"."version" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'Standard' AND type_name = 'Invoice' AND column_name = 'version') THEN
		ALTER TYPE "Standard"."Invoice" ADD ATTRIBUTE "version" BIGINT;
		COMMENT ON COLUMN "Standard"."Invoice"."version" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'Standard' AND type_name = '-ngs_Invoice_type-' AND column_name = 'tax') THEN
		ALTER TYPE "Standard"."-ngs_Invoice_type-" ADD ATTRIBUTE "tax" NUMERIC(22,2);
		COMMENT ON COLUMN "Standard"."-ngs_Invoice_type-"."tax" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'Standard' AND type_name = 'Invoice' AND column_name = 'tax') THEN
		ALTER TYPE "Standard"."Invoice" ADD ATTRIBUTE "tax" NUMERIC(22,2);
		COMMENT ON COLUMN "Standard"."Invoice"."tax" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'Standard' AND type_name = '-ngs_Invoice_type-' AND column_name = 'reference') THEN
		ALTER TYPE "Standard"."-ngs_Invoice_type-" ADD ATTRIBUTE "reference" VARCHAR(15);
		COMMENT ON COLUMN "Standard"."-ngs_Invoice_type-"."reference" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'Standard' AND type_name = 'Invoice' AND column_name = 'reference') THEN
		ALTER TYPE "Standard"."Invoice" ADD ATTRIBUTE "reference" VARCHAR(15);
		COMMENT ON COLUMN "Standard"."Invoice"."reference" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'Standard' AND type_name = '-ngs_Invoice_type-' AND column_name = 'createdAt') THEN
		ALTER TYPE "Standard"."-ngs_Invoice_type-" ADD ATTRIBUTE "createdAt" TIMESTAMPTZ;
		COMMENT ON COLUMN "Standard"."-ngs_Invoice_type-"."createdAt" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'Standard' AND type_name = 'Invoice' AND column_name = 'createdAt') THEN
		ALTER TYPE "Standard"."Invoice" ADD ATTRIBUTE "createdAt" TIMESTAMPTZ;
		COMMENT ON COLUMN "Standard"."Invoice"."createdAt" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'Standard' AND type_name = '-ngs_Invoice_type-' AND column_name = 'modifiedAt') THEN
		ALTER TYPE "Standard"."-ngs_Invoice_type-" ADD ATTRIBUTE "modifiedAt" TIMESTAMPTZ;
		COMMENT ON COLUMN "Standard"."-ngs_Invoice_type-"."modifiedAt" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'Standard' AND type_name = 'Invoice' AND column_name = 'modifiedAt') THEN
		ALTER TYPE "Standard"."Invoice" ADD ATTRIBUTE "modifiedAt" TIMESTAMPTZ;
		COMMENT ON COLUMN "Standard"."Invoice"."modifiedAt" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardObjects' AND type_name = '-ngs_Invoice_type-' AND column_name = 'number') THEN
		ALTER TYPE "StandardObjects"."-ngs_Invoice_type-" ADD ATTRIBUTE "number" VARCHAR(20);
		COMMENT ON COLUMN "StandardObjects"."-ngs_Invoice_type-"."number" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardObjects' AND type_name = 'Invoice' AND column_name = 'number') THEN
		ALTER TABLE "StandardObjects"."Invoice" ADD COLUMN "number" VARCHAR(20);
		COMMENT ON COLUMN "StandardObjects"."Invoice"."number" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardObjects' AND type_name = '-ngs_Invoice_type-' AND column_name = 'items') THEN
		ALTER TYPE "StandardObjects"."-ngs_Invoice_type-" ADD ATTRIBUTE "items" "StandardObjects"."-ngs_Item_type-"[];
		COMMENT ON COLUMN "StandardObjects"."-ngs_Invoice_type-"."items" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardObjects' AND type_name = 'Invoice' AND column_name = 'items') THEN
		ALTER TABLE "StandardObjects"."Invoice" ADD COLUMN "items" "StandardObjects"."Item"[];
		COMMENT ON COLUMN "StandardObjects"."Invoice"."items" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION "StandardObjects"."cast_Item_to_type"("StandardObjects"."Item") RETURNS "StandardObjects"."-ngs_Item_type-" AS $$ SELECT $1::text::"StandardObjects"."-ngs_Item_type-" $$ IMMUTABLE LANGUAGE sql COST 1;
CREATE OR REPLACE FUNCTION "StandardObjects"."cast_Item_to_type"("StandardObjects"."-ngs_Item_type-") RETURNS "StandardObjects"."Item" AS $$ SELECT $1::text::"StandardObjects"."Item" $$ IMMUTABLE LANGUAGE sql COST 1;
CREATE OR REPLACE FUNCTION cast_to_text("StandardObjects"."Item") RETURNS text AS $$ SELECT $1::VARCHAR $$ IMMUTABLE LANGUAGE sql COST 1;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_cast c JOIN pg_type s ON c.castsource = s.oid JOIN pg_type t ON c.casttarget = t.oid JOIN pg_namespace n ON n.oid = s.typnamespace AND n.oid = t.typnamespace
					WHERE n.nspname = 'StandardObjects' AND s.typname = 'Item' AND t.typname = '-ngs_Item_type-') THEN
		CREATE CAST ("StandardObjects"."-ngs_Item_type-" AS "StandardObjects"."Item") WITH FUNCTION "StandardObjects"."cast_Item_to_type"("StandardObjects"."-ngs_Item_type-") AS IMPLICIT;
		CREATE CAST ("StandardObjects"."Item" AS "StandardObjects"."-ngs_Item_type-") WITH FUNCTION "StandardObjects"."cast_Item_to_type"("StandardObjects"."Item") AS IMPLICIT;
		CREATE CAST ("StandardObjects"."Item" AS text) WITH FUNCTION cast_to_text("StandardObjects"."Item") AS ASSIGNMENT;
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardObjects' AND type_name = '-ngs_Item_type-' AND column_name = 'product') THEN
		ALTER TYPE "StandardObjects"."-ngs_Item_type-" ADD ATTRIBUTE "product" VARCHAR(100);
		COMMENT ON COLUMN "StandardObjects"."-ngs_Item_type-"."product" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardObjects' AND type_name = 'Item' AND column_name = 'product') THEN
		ALTER TYPE "StandardObjects"."Item" ADD ATTRIBUTE "product" VARCHAR(100);
		COMMENT ON COLUMN "StandardObjects"."Item"."product" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardObjects' AND type_name = '-ngs_Item_type-' AND column_name = 'cost') THEN
		ALTER TYPE "StandardObjects"."-ngs_Item_type-" ADD ATTRIBUTE "cost" NUMERIC;
		COMMENT ON COLUMN "StandardObjects"."-ngs_Item_type-"."cost" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardObjects' AND type_name = 'Item' AND column_name = 'cost') THEN
		ALTER TYPE "StandardObjects"."Item" ADD ATTRIBUTE "cost" NUMERIC;
		COMMENT ON COLUMN "StandardObjects"."Item"."cost" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardObjects' AND type_name = '-ngs_Item_type-' AND column_name = 'quantity') THEN
		ALTER TYPE "StandardObjects"."-ngs_Item_type-" ADD ATTRIBUTE "quantity" INT;
		COMMENT ON COLUMN "StandardObjects"."-ngs_Item_type-"."quantity" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardObjects' AND type_name = 'Item' AND column_name = 'quantity') THEN
		ALTER TYPE "StandardObjects"."Item" ADD ATTRIBUTE "quantity" INT;
		COMMENT ON COLUMN "StandardObjects"."Item"."quantity" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardObjects' AND type_name = '-ngs_Item_type-' AND column_name = 'taxGroup') THEN
		ALTER TYPE "StandardObjects"."-ngs_Item_type-" ADD ATTRIBUTE "taxGroup" NUMERIC(21, 1);
		COMMENT ON COLUMN "StandardObjects"."-ngs_Item_type-"."taxGroup" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardObjects' AND type_name = 'Item' AND column_name = 'taxGroup') THEN
		ALTER TYPE "StandardObjects"."Item" ADD ATTRIBUTE "taxGroup" NUMERIC(21, 1);
		COMMENT ON COLUMN "StandardObjects"."Item"."taxGroup" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardObjects' AND type_name = '-ngs_Item_type-' AND column_name = 'discount') THEN
		ALTER TYPE "StandardObjects"."-ngs_Item_type-" ADD ATTRIBUTE "discount" NUMERIC(22, 2);
		COMMENT ON COLUMN "StandardObjects"."-ngs_Item_type-"."discount" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardObjects' AND type_name = 'Item' AND column_name = 'discount') THEN
		ALTER TYPE "StandardObjects"."Item" ADD ATTRIBUTE "discount" NUMERIC(22, 2);
		COMMENT ON COLUMN "StandardObjects"."Item"."discount" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardRelations' AND type_name = '-ngs_Invoice_type-' AND column_name = 'number') THEN
		ALTER TYPE "StandardRelations"."-ngs_Invoice_type-" ADD ATTRIBUTE "number" VARCHAR(20);
		COMMENT ON COLUMN "StandardRelations"."-ngs_Invoice_type-"."number" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardRelations' AND type_name = 'Invoice' AND column_name = 'number') THEN
		ALTER TABLE "StandardRelations"."Invoice" ADD COLUMN "number" VARCHAR(20);
		COMMENT ON COLUMN "StandardRelations"."Invoice"."number" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardRelations' AND type_name = '-ngs_Invoice_type-' AND column_name = 'itemsURI') THEN
		ALTER TYPE "StandardRelations"."-ngs_Invoice_type-" ADD ATTRIBUTE "itemsURI" VARCHAR[];
		COMMENT ON COLUMN "StandardRelations"."-ngs_Invoice_type-"."itemsURI" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardRelations' AND type_name = '-ngs_Item_type-' AND column_name = 'product') THEN
		ALTER TYPE "StandardRelations"."-ngs_Item_type-" ADD ATTRIBUTE "product" VARCHAR(100);
		COMMENT ON COLUMN "StandardRelations"."-ngs_Item_type-"."product" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardRelations' AND type_name = 'Item' AND column_name = 'product') THEN
		ALTER TABLE "StandardRelations"."Item" ADD COLUMN "product" VARCHAR(100);
		COMMENT ON COLUMN "StandardRelations"."Item"."product" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardRelations' AND type_name = '-ngs_Item_type-' AND column_name = 'cost') THEN
		ALTER TYPE "StandardRelations"."-ngs_Item_type-" ADD ATTRIBUTE "cost" NUMERIC;
		COMMENT ON COLUMN "StandardRelations"."-ngs_Item_type-"."cost" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardRelations' AND type_name = 'Item' AND column_name = 'cost') THEN
		ALTER TABLE "StandardRelations"."Item" ADD COLUMN "cost" NUMERIC;
		COMMENT ON COLUMN "StandardRelations"."Item"."cost" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardRelations' AND type_name = '-ngs_Item_type-' AND column_name = 'quantity') THEN
		ALTER TYPE "StandardRelations"."-ngs_Item_type-" ADD ATTRIBUTE "quantity" INT;
		COMMENT ON COLUMN "StandardRelations"."-ngs_Item_type-"."quantity" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardRelations' AND type_name = 'Item' AND column_name = 'quantity') THEN
		ALTER TABLE "StandardRelations"."Item" ADD COLUMN "quantity" INT;
		COMMENT ON COLUMN "StandardRelations"."Item"."quantity" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardRelations' AND type_name = '-ngs_Item_type-' AND column_name = 'taxGroup') THEN
		ALTER TYPE "StandardRelations"."-ngs_Item_type-" ADD ATTRIBUTE "taxGroup" NUMERIC(21, 1);
		COMMENT ON COLUMN "StandardRelations"."-ngs_Item_type-"."taxGroup" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardRelations' AND type_name = 'Item' AND column_name = 'taxGroup') THEN
		ALTER TABLE "StandardRelations"."Item" ADD COLUMN "taxGroup" NUMERIC(21, 1);
		COMMENT ON COLUMN "StandardRelations"."Item"."taxGroup" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardRelations' AND type_name = '-ngs_Item_type-' AND column_name = 'discount') THEN
		ALTER TYPE "StandardRelations"."-ngs_Item_type-" ADD ATTRIBUTE "discount" NUMERIC(22, 2);
		COMMENT ON COLUMN "StandardRelations"."-ngs_Item_type-"."discount" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardRelations' AND type_name = 'Item' AND column_name = 'discount') THEN
		ALTER TABLE "StandardRelations"."Item" ADD COLUMN "discount" NUMERIC(22, 2);
		COMMENT ON COLUMN "StandardRelations"."Item"."discount" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = '-ngs_Account_type-' AND column_name = 'BankScrapeid') THEN
		ALTER TYPE "ComplexRelations"."-ngs_Account_type-" ADD ATTRIBUTE "BankScrapeid" INT;
		COMMENT ON COLUMN "ComplexRelations"."-ngs_Account_type-"."BankScrapeid" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = 'Account' AND column_name = 'BankScrapeid') THEN
		ALTER TABLE "ComplexRelations"."Account" ADD COLUMN "BankScrapeid" INT;
		COMMENT ON COLUMN "ComplexRelations"."Account"."BankScrapeid" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = '-ngs_Account_type-' AND column_name = 'Index') THEN
		ALTER TYPE "ComplexRelations"."-ngs_Account_type-" ADD ATTRIBUTE "Index" INT;
		COMMENT ON COLUMN "ComplexRelations"."-ngs_Account_type-"."Index" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = 'Account' AND column_name = 'Index') THEN
		ALTER TABLE "ComplexRelations"."Account" ADD COLUMN "Index" INT;
		COMMENT ON COLUMN "ComplexRelations"."Account"."Index" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = '-ngs_Transaction_type-' AND column_name = 'AccountBankScrapeid') THEN
		ALTER TYPE "ComplexRelations"."-ngs_Transaction_type-" ADD ATTRIBUTE "AccountBankScrapeid" INT;
		COMMENT ON COLUMN "ComplexRelations"."-ngs_Transaction_type-"."AccountBankScrapeid" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = 'Transaction' AND column_name = 'AccountBankScrapeid') THEN
		ALTER TABLE "ComplexRelations"."Transaction" ADD COLUMN "AccountBankScrapeid" INT;
		COMMENT ON COLUMN "ComplexRelations"."Transaction"."AccountBankScrapeid" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = '-ngs_Transaction_type-' AND column_name = 'AccountIndex') THEN
		ALTER TYPE "ComplexRelations"."-ngs_Transaction_type-" ADD ATTRIBUTE "AccountIndex" INT;
		COMMENT ON COLUMN "ComplexRelations"."-ngs_Transaction_type-"."AccountIndex" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = 'Transaction' AND column_name = 'AccountIndex') THEN
		ALTER TABLE "ComplexRelations"."Transaction" ADD COLUMN "AccountIndex" INT;
		COMMENT ON COLUMN "ComplexRelations"."Transaction"."AccountIndex" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = '-ngs_Transaction_type-' AND column_name = 'Index') THEN
		ALTER TYPE "ComplexRelations"."-ngs_Transaction_type-" ADD ATTRIBUTE "Index" INT;
		COMMENT ON COLUMN "ComplexRelations"."-ngs_Transaction_type-"."Index" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = 'Transaction' AND column_name = 'Index') THEN
		ALTER TABLE "ComplexRelations"."Transaction" ADD COLUMN "Index" INT;
		COMMENT ON COLUMN "ComplexRelations"."Transaction"."Index" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardRelations' AND type_name = '-ngs_Item_type-' AND column_name = 'Invoicenumber') THEN
		ALTER TYPE "StandardRelations"."-ngs_Item_type-" ADD ATTRIBUTE "Invoicenumber" VARCHAR(20);
		COMMENT ON COLUMN "StandardRelations"."-ngs_Item_type-"."Invoicenumber" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardRelations' AND type_name = 'Item' AND column_name = 'Invoicenumber') THEN
		ALTER TABLE "StandardRelations"."Item" ADD COLUMN "Invoicenumber" VARCHAR(20);
		COMMENT ON COLUMN "StandardRelations"."Item"."Invoicenumber" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardRelations' AND type_name = '-ngs_Item_type-' AND column_name = 'Index') THEN
		ALTER TYPE "StandardRelations"."-ngs_Item_type-" ADD ATTRIBUTE "Index" INT;
		COMMENT ON COLUMN "StandardRelations"."-ngs_Item_type-"."Index" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardRelations' AND type_name = 'Item' AND column_name = 'Index') THEN
		ALTER TABLE "StandardRelations"."Item" ADD COLUMN "Index" INT;
		COMMENT ON COLUMN "StandardRelations"."Item"."Index" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexObjects' AND type_name = '-ngs_BankScrape_type-' AND column_name = 'website') THEN
		ALTER TYPE "ComplexObjects"."-ngs_BankScrape_type-" ADD ATTRIBUTE "website" VARCHAR;
		COMMENT ON COLUMN "ComplexObjects"."-ngs_BankScrape_type-"."website" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexObjects' AND type_name = 'BankScrape' AND column_name = 'website') THEN
		ALTER TABLE "ComplexObjects"."BankScrape" ADD COLUMN "website" VARCHAR;
		COMMENT ON COLUMN "ComplexObjects"."BankScrape"."website" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexObjects' AND type_name = '-ngs_BankScrape_type-' AND column_name = 'at') THEN
		ALTER TYPE "ComplexObjects"."-ngs_BankScrape_type-" ADD ATTRIBUTE "at" TIMESTAMPTZ;
		COMMENT ON COLUMN "ComplexObjects"."-ngs_BankScrape_type-"."at" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexObjects' AND type_name = 'BankScrape' AND column_name = 'at') THEN
		ALTER TABLE "ComplexObjects"."BankScrape" ADD COLUMN "at" TIMESTAMPTZ;
		COMMENT ON COLUMN "ComplexObjects"."BankScrape"."at" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexObjects' AND type_name = '-ngs_BankScrape_type-' AND column_name = 'info') THEN
		ALTER TYPE "ComplexObjects"."-ngs_BankScrape_type-" ADD ATTRIBUTE "info" HSTORE;
		COMMENT ON COLUMN "ComplexObjects"."-ngs_BankScrape_type-"."info" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexObjects' AND type_name = 'BankScrape' AND column_name = 'info') THEN
		ALTER TABLE "ComplexObjects"."BankScrape" ADD COLUMN "info" HSTORE;
		COMMENT ON COLUMN "ComplexObjects"."BankScrape"."info" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexObjects' AND type_name = '-ngs_BankScrape_type-' AND column_name = 'externalId') THEN
		ALTER TYPE "ComplexObjects"."-ngs_BankScrape_type-" ADD ATTRIBUTE "externalId" VARCHAR(50);
		COMMENT ON COLUMN "ComplexObjects"."-ngs_BankScrape_type-"."externalId" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexObjects' AND type_name = 'BankScrape' AND column_name = 'externalId') THEN
		ALTER TABLE "ComplexObjects"."BankScrape" ADD COLUMN "externalId" VARCHAR(50);
		COMMENT ON COLUMN "ComplexObjects"."BankScrape"."externalId" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexObjects' AND type_name = '-ngs_BankScrape_type-' AND column_name = 'ranking') THEN
		ALTER TYPE "ComplexObjects"."-ngs_BankScrape_type-" ADD ATTRIBUTE "ranking" INT;
		COMMENT ON COLUMN "ComplexObjects"."-ngs_BankScrape_type-"."ranking" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexObjects' AND type_name = 'BankScrape' AND column_name = 'ranking') THEN
		ALTER TABLE "ComplexObjects"."BankScrape" ADD COLUMN "ranking" INT;
		COMMENT ON COLUMN "ComplexObjects"."BankScrape"."ranking" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexObjects' AND type_name = '-ngs_BankScrape_type-' AND column_name = 'tags') THEN
		ALTER TYPE "ComplexObjects"."-ngs_BankScrape_type-" ADD ATTRIBUTE "tags" VARCHAR(10)[];
		COMMENT ON COLUMN "ComplexObjects"."-ngs_BankScrape_type-"."tags" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexObjects' AND type_name = 'BankScrape' AND column_name = 'tags') THEN
		ALTER TABLE "ComplexObjects"."BankScrape" ADD COLUMN "tags" VARCHAR(10)[];
		COMMENT ON COLUMN "ComplexObjects"."BankScrape"."tags" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexObjects' AND type_name = '-ngs_BankScrape_type-' AND column_name = 'createdAt') THEN
		ALTER TYPE "ComplexObjects"."-ngs_BankScrape_type-" ADD ATTRIBUTE "createdAt" TIMESTAMPTZ;
		COMMENT ON COLUMN "ComplexObjects"."-ngs_BankScrape_type-"."createdAt" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexObjects' AND type_name = 'BankScrape' AND column_name = 'createdAt') THEN
		ALTER TABLE "ComplexObjects"."BankScrape" ADD COLUMN "createdAt" TIMESTAMPTZ;
		COMMENT ON COLUMN "ComplexObjects"."BankScrape"."createdAt" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = '-ngs_BankScrape_type-' AND column_name = 'website') THEN
		ALTER TYPE "ComplexRelations"."-ngs_BankScrape_type-" ADD ATTRIBUTE "website" VARCHAR;
		COMMENT ON COLUMN "ComplexRelations"."-ngs_BankScrape_type-"."website" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = 'BankScrape' AND column_name = 'website') THEN
		ALTER TABLE "ComplexRelations"."BankScrape" ADD COLUMN "website" VARCHAR;
		COMMENT ON COLUMN "ComplexRelations"."BankScrape"."website" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = '-ngs_BankScrape_type-' AND column_name = 'at') THEN
		ALTER TYPE "ComplexRelations"."-ngs_BankScrape_type-" ADD ATTRIBUTE "at" TIMESTAMPTZ;
		COMMENT ON COLUMN "ComplexRelations"."-ngs_BankScrape_type-"."at" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = 'BankScrape' AND column_name = 'at') THEN
		ALTER TABLE "ComplexRelations"."BankScrape" ADD COLUMN "at" TIMESTAMPTZ;
		COMMENT ON COLUMN "ComplexRelations"."BankScrape"."at" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = '-ngs_BankScrape_type-' AND column_name = 'info') THEN
		ALTER TYPE "ComplexRelations"."-ngs_BankScrape_type-" ADD ATTRIBUTE "info" HSTORE;
		COMMENT ON COLUMN "ComplexRelations"."-ngs_BankScrape_type-"."info" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = 'BankScrape' AND column_name = 'info') THEN
		ALTER TABLE "ComplexRelations"."BankScrape" ADD COLUMN "info" HSTORE;
		COMMENT ON COLUMN "ComplexRelations"."BankScrape"."info" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = '-ngs_BankScrape_type-' AND column_name = 'externalId') THEN
		ALTER TYPE "ComplexRelations"."-ngs_BankScrape_type-" ADD ATTRIBUTE "externalId" VARCHAR(50);
		COMMENT ON COLUMN "ComplexRelations"."-ngs_BankScrape_type-"."externalId" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = 'BankScrape' AND column_name = 'externalId') THEN
		ALTER TABLE "ComplexRelations"."BankScrape" ADD COLUMN "externalId" VARCHAR(50);
		COMMENT ON COLUMN "ComplexRelations"."BankScrape"."externalId" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = '-ngs_BankScrape_type-' AND column_name = 'ranking') THEN
		ALTER TYPE "ComplexRelations"."-ngs_BankScrape_type-" ADD ATTRIBUTE "ranking" INT;
		COMMENT ON COLUMN "ComplexRelations"."-ngs_BankScrape_type-"."ranking" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = 'BankScrape' AND column_name = 'ranking') THEN
		ALTER TABLE "ComplexRelations"."BankScrape" ADD COLUMN "ranking" INT;
		COMMENT ON COLUMN "ComplexRelations"."BankScrape"."ranking" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = '-ngs_BankScrape_type-' AND column_name = 'tags') THEN
		ALTER TYPE "ComplexRelations"."-ngs_BankScrape_type-" ADD ATTRIBUTE "tags" VARCHAR(10)[];
		COMMENT ON COLUMN "ComplexRelations"."-ngs_BankScrape_type-"."tags" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = 'BankScrape' AND column_name = 'tags') THEN
		ALTER TABLE "ComplexRelations"."BankScrape" ADD COLUMN "tags" VARCHAR(10)[];
		COMMENT ON COLUMN "ComplexRelations"."BankScrape"."tags" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = '-ngs_BankScrape_type-' AND column_name = 'createdAt') THEN
		ALTER TYPE "ComplexRelations"."-ngs_BankScrape_type-" ADD ATTRIBUTE "createdAt" TIMESTAMPTZ;
		COMMENT ON COLUMN "ComplexRelations"."-ngs_BankScrape_type-"."createdAt" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = 'BankScrape' AND column_name = 'createdAt') THEN
		ALTER TABLE "ComplexRelations"."BankScrape" ADD COLUMN "createdAt" TIMESTAMPTZ;
		COMMENT ON COLUMN "ComplexRelations"."BankScrape"."createdAt" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardObjects' AND type_name = '-ngs_Invoice_type-' AND column_name = 'dueDate') THEN
		ALTER TYPE "StandardObjects"."-ngs_Invoice_type-" ADD ATTRIBUTE "dueDate" DATE;
		COMMENT ON COLUMN "StandardObjects"."-ngs_Invoice_type-"."dueDate" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardObjects' AND type_name = 'Invoice' AND column_name = 'dueDate') THEN
		ALTER TABLE "StandardObjects"."Invoice" ADD COLUMN "dueDate" DATE;
		COMMENT ON COLUMN "StandardObjects"."Invoice"."dueDate" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardObjects' AND type_name = '-ngs_Invoice_type-' AND column_name = 'total') THEN
		ALTER TYPE "StandardObjects"."-ngs_Invoice_type-" ADD ATTRIBUTE "total" NUMERIC;
		COMMENT ON COLUMN "StandardObjects"."-ngs_Invoice_type-"."total" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardObjects' AND type_name = 'Invoice' AND column_name = 'total') THEN
		ALTER TABLE "StandardObjects"."Invoice" ADD COLUMN "total" NUMERIC;
		COMMENT ON COLUMN "StandardObjects"."Invoice"."total" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardObjects' AND type_name = '-ngs_Invoice_type-' AND column_name = 'paid') THEN
		ALTER TYPE "StandardObjects"."-ngs_Invoice_type-" ADD ATTRIBUTE "paid" TIMESTAMPTZ;
		COMMENT ON COLUMN "StandardObjects"."-ngs_Invoice_type-"."paid" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardObjects' AND type_name = 'Invoice' AND column_name = 'paid') THEN
		ALTER TABLE "StandardObjects"."Invoice" ADD COLUMN "paid" TIMESTAMPTZ;
		COMMENT ON COLUMN "StandardObjects"."Invoice"."paid" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardObjects' AND type_name = '-ngs_Invoice_type-' AND column_name = 'canceled') THEN
		ALTER TYPE "StandardObjects"."-ngs_Invoice_type-" ADD ATTRIBUTE "canceled" BOOL;
		COMMENT ON COLUMN "StandardObjects"."-ngs_Invoice_type-"."canceled" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardObjects' AND type_name = 'Invoice' AND column_name = 'canceled') THEN
		ALTER TABLE "StandardObjects"."Invoice" ADD COLUMN "canceled" BOOL;
		COMMENT ON COLUMN "StandardObjects"."Invoice"."canceled" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardObjects' AND type_name = '-ngs_Invoice_type-' AND column_name = 'version') THEN
		ALTER TYPE "StandardObjects"."-ngs_Invoice_type-" ADD ATTRIBUTE "version" BIGINT;
		COMMENT ON COLUMN "StandardObjects"."-ngs_Invoice_type-"."version" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardObjects' AND type_name = 'Invoice' AND column_name = 'version') THEN
		ALTER TABLE "StandardObjects"."Invoice" ADD COLUMN "version" BIGINT;
		COMMENT ON COLUMN "StandardObjects"."Invoice"."version" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardObjects' AND type_name = '-ngs_Invoice_type-' AND column_name = 'tax') THEN
		ALTER TYPE "StandardObjects"."-ngs_Invoice_type-" ADD ATTRIBUTE "tax" NUMERIC(22,2);
		COMMENT ON COLUMN "StandardObjects"."-ngs_Invoice_type-"."tax" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardObjects' AND type_name = 'Invoice' AND column_name = 'tax') THEN
		ALTER TABLE "StandardObjects"."Invoice" ADD COLUMN "tax" NUMERIC(22,2);
		COMMENT ON COLUMN "StandardObjects"."Invoice"."tax" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardObjects' AND type_name = '-ngs_Invoice_type-' AND column_name = 'reference') THEN
		ALTER TYPE "StandardObjects"."-ngs_Invoice_type-" ADD ATTRIBUTE "reference" VARCHAR(15);
		COMMENT ON COLUMN "StandardObjects"."-ngs_Invoice_type-"."reference" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardObjects' AND type_name = 'Invoice' AND column_name = 'reference') THEN
		ALTER TABLE "StandardObjects"."Invoice" ADD COLUMN "reference" VARCHAR(15);
		COMMENT ON COLUMN "StandardObjects"."Invoice"."reference" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardObjects' AND type_name = '-ngs_Invoice_type-' AND column_name = 'createdAt') THEN
		ALTER TYPE "StandardObjects"."-ngs_Invoice_type-" ADD ATTRIBUTE "createdAt" TIMESTAMPTZ;
		COMMENT ON COLUMN "StandardObjects"."-ngs_Invoice_type-"."createdAt" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardObjects' AND type_name = 'Invoice' AND column_name = 'createdAt') THEN
		ALTER TABLE "StandardObjects"."Invoice" ADD COLUMN "createdAt" TIMESTAMPTZ;
		COMMENT ON COLUMN "StandardObjects"."Invoice"."createdAt" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardObjects' AND type_name = '-ngs_Invoice_type-' AND column_name = 'modifiedAt') THEN
		ALTER TYPE "StandardObjects"."-ngs_Invoice_type-" ADD ATTRIBUTE "modifiedAt" TIMESTAMPTZ;
		COMMENT ON COLUMN "StandardObjects"."-ngs_Invoice_type-"."modifiedAt" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardObjects' AND type_name = 'Invoice' AND column_name = 'modifiedAt') THEN
		ALTER TABLE "StandardObjects"."Invoice" ADD COLUMN "modifiedAt" TIMESTAMPTZ;
		COMMENT ON COLUMN "StandardObjects"."Invoice"."modifiedAt" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardRelations' AND type_name = '-ngs_Invoice_type-' AND column_name = 'dueDate') THEN
		ALTER TYPE "StandardRelations"."-ngs_Invoice_type-" ADD ATTRIBUTE "dueDate" DATE;
		COMMENT ON COLUMN "StandardRelations"."-ngs_Invoice_type-"."dueDate" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardRelations' AND type_name = 'Invoice' AND column_name = 'dueDate') THEN
		ALTER TABLE "StandardRelations"."Invoice" ADD COLUMN "dueDate" DATE;
		COMMENT ON COLUMN "StandardRelations"."Invoice"."dueDate" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardRelations' AND type_name = '-ngs_Invoice_type-' AND column_name = 'total') THEN
		ALTER TYPE "StandardRelations"."-ngs_Invoice_type-" ADD ATTRIBUTE "total" NUMERIC;
		COMMENT ON COLUMN "StandardRelations"."-ngs_Invoice_type-"."total" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardRelations' AND type_name = 'Invoice' AND column_name = 'total') THEN
		ALTER TABLE "StandardRelations"."Invoice" ADD COLUMN "total" NUMERIC;
		COMMENT ON COLUMN "StandardRelations"."Invoice"."total" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardRelations' AND type_name = '-ngs_Invoice_type-' AND column_name = 'paid') THEN
		ALTER TYPE "StandardRelations"."-ngs_Invoice_type-" ADD ATTRIBUTE "paid" TIMESTAMPTZ;
		COMMENT ON COLUMN "StandardRelations"."-ngs_Invoice_type-"."paid" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardRelations' AND type_name = 'Invoice' AND column_name = 'paid') THEN
		ALTER TABLE "StandardRelations"."Invoice" ADD COLUMN "paid" TIMESTAMPTZ;
		COMMENT ON COLUMN "StandardRelations"."Invoice"."paid" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardRelations' AND type_name = '-ngs_Invoice_type-' AND column_name = 'canceled') THEN
		ALTER TYPE "StandardRelations"."-ngs_Invoice_type-" ADD ATTRIBUTE "canceled" BOOL;
		COMMENT ON COLUMN "StandardRelations"."-ngs_Invoice_type-"."canceled" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardRelations' AND type_name = 'Invoice' AND column_name = 'canceled') THEN
		ALTER TABLE "StandardRelations"."Invoice" ADD COLUMN "canceled" BOOL;
		COMMENT ON COLUMN "StandardRelations"."Invoice"."canceled" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardRelations' AND type_name = '-ngs_Invoice_type-' AND column_name = 'version') THEN
		ALTER TYPE "StandardRelations"."-ngs_Invoice_type-" ADD ATTRIBUTE "version" BIGINT;
		COMMENT ON COLUMN "StandardRelations"."-ngs_Invoice_type-"."version" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardRelations' AND type_name = 'Invoice' AND column_name = 'version') THEN
		ALTER TABLE "StandardRelations"."Invoice" ADD COLUMN "version" BIGINT;
		COMMENT ON COLUMN "StandardRelations"."Invoice"."version" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardRelations' AND type_name = '-ngs_Invoice_type-' AND column_name = 'tax') THEN
		ALTER TYPE "StandardRelations"."-ngs_Invoice_type-" ADD ATTRIBUTE "tax" NUMERIC(22,2);
		COMMENT ON COLUMN "StandardRelations"."-ngs_Invoice_type-"."tax" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardRelations' AND type_name = 'Invoice' AND column_name = 'tax') THEN
		ALTER TABLE "StandardRelations"."Invoice" ADD COLUMN "tax" NUMERIC(22,2);
		COMMENT ON COLUMN "StandardRelations"."Invoice"."tax" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardRelations' AND type_name = '-ngs_Invoice_type-' AND column_name = 'reference') THEN
		ALTER TYPE "StandardRelations"."-ngs_Invoice_type-" ADD ATTRIBUTE "reference" VARCHAR(15);
		COMMENT ON COLUMN "StandardRelations"."-ngs_Invoice_type-"."reference" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardRelations' AND type_name = 'Invoice' AND column_name = 'reference') THEN
		ALTER TABLE "StandardRelations"."Invoice" ADD COLUMN "reference" VARCHAR(15);
		COMMENT ON COLUMN "StandardRelations"."Invoice"."reference" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardRelations' AND type_name = '-ngs_Invoice_type-' AND column_name = 'createdAt') THEN
		ALTER TYPE "StandardRelations"."-ngs_Invoice_type-" ADD ATTRIBUTE "createdAt" TIMESTAMPTZ;
		COMMENT ON COLUMN "StandardRelations"."-ngs_Invoice_type-"."createdAt" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardRelations' AND type_name = 'Invoice' AND column_name = 'createdAt') THEN
		ALTER TABLE "StandardRelations"."Invoice" ADD COLUMN "createdAt" TIMESTAMPTZ;
		COMMENT ON COLUMN "StandardRelations"."Invoice"."createdAt" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardRelations' AND type_name = '-ngs_Invoice_type-' AND column_name = 'modifiedAt') THEN
		ALTER TYPE "StandardRelations"."-ngs_Invoice_type-" ADD ATTRIBUTE "modifiedAt" TIMESTAMPTZ;
		COMMENT ON COLUMN "StandardRelations"."-ngs_Invoice_type-"."modifiedAt" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardRelations' AND type_name = 'Invoice' AND column_name = 'modifiedAt') THEN
		ALTER TABLE "StandardRelations"."Invoice" ADD COLUMN "modifiedAt" TIMESTAMPTZ;
		COMMENT ON COLUMN "StandardRelations"."Invoice"."modifiedAt" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = '-ngs_Account_type-' AND column_name = 'transactions') THEN
		ALTER TYPE "ComplexRelations"."-ngs_Account_type-" ADD ATTRIBUTE "transactions" "ComplexRelations"."-ngs_Transaction_type-"[];
		COMMENT ON COLUMN "ComplexRelations"."-ngs_Account_type-"."transactions" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardRelations' AND type_name = '-ngs_Invoice_type-' AND column_name = 'items') THEN
		ALTER TYPE "StandardRelations"."-ngs_Invoice_type-" ADD ATTRIBUTE "items" "StandardRelations"."-ngs_Item_type-"[];
		COMMENT ON COLUMN "StandardRelations"."-ngs_Invoice_type-"."items" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = '-ngs_BankScrape_type-' AND column_name = 'accounts') THEN
		ALTER TYPE "ComplexRelations"."-ngs_BankScrape_type-" ADD ATTRIBUTE "accounts" "ComplexRelations"."-ngs_Account_type-"[];
		COMMENT ON COLUMN "ComplexRelations"."-ngs_BankScrape_type-"."accounts" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE VIEW "ComplexObjects"."BankScrape_entity" AS
SELECT _entity."id", _entity."accounts", _entity."website", _entity."at", _entity."info", _entity."externalId", _entity."ranking", _entity."tags", _entity."createdAt"
FROM
	"ComplexObjects"."BankScrape" _entity
	;
COMMENT ON VIEW "ComplexObjects"."BankScrape_entity" IS 'NGS volatile';

CREATE OR REPLACE FUNCTION "URI"("ComplexObjects"."BankScrape_entity") RETURNS TEXT AS $$
SELECT CAST($1."id" as TEXT)
$$ LANGUAGE SQL IMMUTABLE SECURITY DEFINER;

CREATE OR REPLACE VIEW "ComplexRelations"."Transaction_entity" AS
SELECT _entity."date", _entity."description", _entity."currency", _entity."amount", _entity."AccountBankScrapeid", _entity."AccountIndex", _entity."Index"
FROM
	"ComplexRelations"."Transaction" _entity
	;
COMMENT ON VIEW "ComplexRelations"."Transaction_entity" IS 'NGS volatile';

CREATE OR REPLACE FUNCTION "URI"("ComplexRelations"."Transaction_entity") RETURNS TEXT AS $$
SELECT "-NGS-".Generate_Uri3(CAST($1."AccountBankScrapeid" as TEXT), CAST($1."AccountIndex" as TEXT), CAST($1."Index" as TEXT))
$$ LANGUAGE SQL IMMUTABLE SECURITY DEFINER;

CREATE OR REPLACE VIEW "Simple"."Post_entity" AS
SELECT _entity."id", _entity."title", _entity."created"
FROM
	"Simple"."Post" _entity
	;
COMMENT ON VIEW "Simple"."Post_entity" IS 'NGS volatile';

CREATE OR REPLACE FUNCTION "URI"("Simple"."Post_entity") RETURNS TEXT AS $$
SELECT CAST($1."id" as TEXT)
$$ LANGUAGE SQL IMMUTABLE SECURITY DEFINER;

CREATE OR REPLACE VIEW "StandardObjects"."Invoice_entity" AS
SELECT _entity."number", _entity."items", _entity."dueDate", _entity."total", _entity."paid", _entity."canceled", _entity."version", _entity."tax", _entity."reference", _entity."createdAt", _entity."modifiedAt"
FROM
	"StandardObjects"."Invoice" _entity
	;
COMMENT ON VIEW "StandardObjects"."Invoice_entity" IS 'NGS volatile';

CREATE OR REPLACE FUNCTION "URI"("StandardObjects"."Invoice_entity") RETURNS TEXT AS $$
SELECT CAST($1."number" as TEXT)
$$ LANGUAGE SQL IMMUTABLE SECURITY DEFINER;

CREATE OR REPLACE VIEW "StandardRelations"."Item_entity" AS
SELECT _entity."product", _entity."cost", _entity."quantity", _entity."taxGroup", _entity."discount", _entity."Invoicenumber", _entity."Index"
FROM
	"StandardRelations"."Item" _entity
	;
COMMENT ON VIEW "StandardRelations"."Item_entity" IS 'NGS volatile';

CREATE OR REPLACE FUNCTION "URI"("StandardRelations"."Item_entity") RETURNS TEXT AS $$
SELECT "-NGS-".Generate_Uri2(CAST($1."Invoicenumber" as TEXT), CAST($1."Index" as TEXT))
$$ LANGUAGE SQL IMMUTABLE SECURITY DEFINER;

CREATE OR REPLACE VIEW "ComplexRelations"."Account_entity" AS
SELECT _entity."balance", _entity."number", _entity."name", _entity."notes", COALESCE((SELECT array_agg(sq ORDER BY sq."Index") FROM "ComplexRelations"."Transaction_entity" sq WHERE sq."AccountBankScrapeid" = _entity."BankScrapeid" AND sq."AccountIndex" = _entity."Index"), '{}') AS "transactions", _entity."BankScrapeid", _entity."Index"
FROM
	"ComplexRelations"."Account" _entity
	;
COMMENT ON VIEW "ComplexRelations"."Account_entity" IS 'NGS volatile';

CREATE OR REPLACE FUNCTION "URI"("ComplexRelations"."Account_entity") RETURNS TEXT AS $$
SELECT "-NGS-".Generate_Uri2(CAST($1."BankScrapeid" as TEXT), CAST($1."Index" as TEXT))
$$ LANGUAGE SQL IMMUTABLE SECURITY DEFINER;

CREATE OR REPLACE VIEW "StandardRelations"."Invoice_entity" AS
SELECT _entity."number", COALESCE((SELECT array_agg(sq ORDER BY sq."Index") FROM "StandardRelations"."Item_entity" sq WHERE sq."Invoicenumber" = _entity."number"), '{}') AS "items", _entity."dueDate", _entity."total", _entity."paid", _entity."canceled", _entity."version", _entity."tax", _entity."reference", _entity."createdAt", _entity."modifiedAt"
FROM
	"StandardRelations"."Invoice" _entity
	;
COMMENT ON VIEW "StandardRelations"."Invoice_entity" IS 'NGS volatile';

CREATE OR REPLACE FUNCTION "URI"("StandardRelations"."Invoice_entity") RETURNS TEXT AS $$
SELECT CAST($1."number" as TEXT)
$$ LANGUAGE SQL IMMUTABLE SECURITY DEFINER;

CREATE OR REPLACE VIEW "ComplexRelations"."BankScrape_entity" AS
SELECT _entity."id", COALESCE((SELECT array_agg(sq ORDER BY sq."Index") FROM "ComplexRelations"."Account_entity" sq WHERE sq."BankScrapeid" = _entity."id"), '{}') AS "accounts", _entity."website", _entity."at", _entity."info", _entity."externalId", _entity."ranking", _entity."tags", _entity."createdAt"
FROM
	"ComplexRelations"."BankScrape" _entity
	;
COMMENT ON VIEW "ComplexRelations"."BankScrape_entity" IS 'NGS volatile';

CREATE OR REPLACE FUNCTION "URI"("ComplexRelations"."BankScrape_entity") RETURNS TEXT AS $$
SELECT CAST($1."id" as TEXT)
$$ LANGUAGE SQL IMMUTABLE SECURITY DEFINER;

CREATE OR REPLACE FUNCTION "ComplexObjects"."cast_BankScrape_to_type"("ComplexObjects"."-ngs_BankScrape_type-") RETURNS "ComplexObjects"."BankScrape_entity" AS $$ SELECT $1::text::"ComplexObjects"."BankScrape_entity" $$ IMMUTABLE LANGUAGE sql;
CREATE OR REPLACE FUNCTION "ComplexObjects"."cast_BankScrape_to_type"("ComplexObjects"."BankScrape_entity") RETURNS "ComplexObjects"."-ngs_BankScrape_type-" AS $$ SELECT $1::text::"ComplexObjects"."-ngs_BankScrape_type-" $$ IMMUTABLE LANGUAGE sql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_cast c JOIN pg_type s ON c.castsource = s.oid JOIN pg_type t ON c.casttarget = t.oid JOIN pg_namespace n ON n.oid = s.typnamespace AND n.oid = t.typnamespace
					WHERE n.nspname = 'ComplexObjects' AND s.typname = 'BankScrape_entity' AND t.typname = '-ngs_BankScrape_type-') THEN
		CREATE CAST ("ComplexObjects"."-ngs_BankScrape_type-" AS "ComplexObjects"."BankScrape_entity") WITH FUNCTION "ComplexObjects"."cast_BankScrape_to_type"("ComplexObjects"."-ngs_BankScrape_type-") AS IMPLICIT;
		CREATE CAST ("ComplexObjects"."BankScrape_entity" AS "ComplexObjects"."-ngs_BankScrape_type-") WITH FUNCTION "ComplexObjects"."cast_BankScrape_to_type"("ComplexObjects"."BankScrape_entity") AS IMPLICIT;
	END IF;
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION "ComplexObjects"."insert_BankScrape"(IN _inserted "ComplexObjects"."BankScrape_entity"[]) RETURNS VOID AS
$$
BEGIN
	INSERT INTO "ComplexObjects"."BankScrape" ("id", "accounts", "website", "at", "info", "externalId", "ranking", "tags", "createdAt") VALUES(_inserted[1]."id", _inserted[1]."accounts", _inserted[1]."website", _inserted[1]."at", _inserted[1]."info", _inserted[1]."externalId", _inserted[1]."ranking", _inserted[1]."tags", _inserted[1]."createdAt");
	
END
$$
LANGUAGE plpgsql SECURITY DEFINER;;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexObjects' AND type_name = '>update-BankScrape-pair<' AND column_name = 'original') THEN
		DROP TYPE IF EXISTS "ComplexObjects".">update-BankScrape-pair<";
		CREATE TYPE "ComplexObjects".">update-BankScrape-pair<" AS (original "ComplexObjects"."BankScrape_entity", changed "ComplexObjects"."BankScrape_entity");
	END IF;
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION "ComplexObjects"."persist_BankScrape"(
IN _inserted "ComplexObjects"."BankScrape_entity"[], IN _updated "ComplexObjects".">update-BankScrape-pair<"[], IN _deleted "ComplexObjects"."BankScrape_entity"[]) 
	RETURNS VARCHAR AS
$$
DECLARE cnt int;
DECLARE uri VARCHAR;
DECLARE tmp record;
DECLARE _update_count int = array_upper(_updated, 1);
DECLARE _delete_count int = array_upper(_deleted, 1);

BEGIN

	SET CONSTRAINTS ALL DEFERRED;

	

	INSERT INTO "ComplexObjects"."BankScrape" ("id", "accounts", "website", "at", "info", "externalId", "ranking", "tags", "createdAt")
	SELECT _i."id", _i."accounts", _i."website", _i."at", _i."info", _i."externalId", _i."ranking", _i."tags", _i."createdAt" 
	FROM unnest(_inserted) _i;

	

	UPDATE "ComplexObjects"."BankScrape" as _tbl SET "id" = (_u.changed)."id", "accounts" = (_u.changed)."accounts", "website" = (_u.changed)."website", "at" = (_u.changed)."at", "info" = (_u.changed)."info", "externalId" = (_u.changed)."externalId", "ranking" = (_u.changed)."ranking", "tags" = (_u.changed)."tags", "createdAt" = (_u.changed)."createdAt"
	FROM unnest(_updated) _u
	WHERE _tbl."id" = (_u.original)."id";

	GET DIAGNOSTICS cnt = ROW_COUNT;
	IF cnt != _update_count THEN 
		RETURN 'Updated ' || cnt || ' row(s). Expected to update ' || _update_count || ' row(s).';
	END IF;

	

	DELETE FROM "ComplexObjects"."BankScrape"
	WHERE ("id") IN (SELECT _d."id" FROM unnest(_deleted) _d);

	GET DIAGNOSTICS cnt = ROW_COUNT;
	IF cnt != _delete_count THEN 
		RETURN 'Deleted ' || cnt || ' row(s). Expected to delete ' || _delete_count || ' row(s).';
	END IF;

	

	SET CONSTRAINTS ALL IMMEDIATE;

	RETURN NULL;
END
$$
LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION "ComplexObjects"."update_BankScrape"(IN _original "ComplexObjects"."BankScrape_entity"[], IN _updated "ComplexObjects"."BankScrape_entity"[]) RETURNS VARCHAR AS
$$
BEGIN
	
	UPDATE "ComplexObjects"."BankScrape" AS _tab SET "id" = _updated[1]."id", "accounts" = _updated[1]."accounts", "website" = _updated[1]."website", "at" = _updated[1]."at", "info" = _updated[1]."info", "externalId" = _updated[1]."externalId", "ranking" = _updated[1]."ranking", "tags" = _updated[1]."tags", "createdAt" = _updated[1]."createdAt" WHERE _tab."id" = _original[1]."id";
	
	RETURN NULL;
END
$$
LANGUAGE plpgsql SECURITY DEFINER;;

CREATE OR REPLACE VIEW "ComplexObjects"."BankScrape_unprocessed_events" AS
SELECT _aggregate."id"
FROM
	"ComplexObjects"."BankScrape_entity" _aggregate
;
COMMENT ON VIEW "ComplexObjects"."BankScrape_unprocessed_events" IS 'NGS volatile';

CREATE OR REPLACE FUNCTION "ComplexRelations"."cast_Transaction_to_type"("ComplexRelations"."-ngs_Transaction_type-") RETURNS "ComplexRelations"."Transaction_entity" AS $$ SELECT $1::text::"ComplexRelations"."Transaction_entity" $$ IMMUTABLE LANGUAGE sql;
CREATE OR REPLACE FUNCTION "ComplexRelations"."cast_Transaction_to_type"("ComplexRelations"."Transaction_entity") RETURNS "ComplexRelations"."-ngs_Transaction_type-" AS $$ SELECT $1::text::"ComplexRelations"."-ngs_Transaction_type-" $$ IMMUTABLE LANGUAGE sql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_cast c JOIN pg_type s ON c.castsource = s.oid JOIN pg_type t ON c.casttarget = t.oid JOIN pg_namespace n ON n.oid = s.typnamespace AND n.oid = t.typnamespace
					WHERE n.nspname = 'ComplexRelations' AND s.typname = 'Transaction_entity' AND t.typname = '-ngs_Transaction_type-') THEN
		CREATE CAST ("ComplexRelations"."-ngs_Transaction_type-" AS "ComplexRelations"."Transaction_entity") WITH FUNCTION "ComplexRelations"."cast_Transaction_to_type"("ComplexRelations"."-ngs_Transaction_type-") AS IMPLICIT;
		CREATE CAST ("ComplexRelations"."Transaction_entity" AS "ComplexRelations"."-ngs_Transaction_type-") WITH FUNCTION "ComplexRelations"."cast_Transaction_to_type"("ComplexRelations"."Transaction_entity") AS IMPLICIT;
	END IF;
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION "Simple"."cast_Post_to_type"("Simple"."-ngs_Post_type-") RETURNS "Simple"."Post_entity" AS $$ SELECT $1::text::"Simple"."Post_entity" $$ IMMUTABLE LANGUAGE sql;
CREATE OR REPLACE FUNCTION "Simple"."cast_Post_to_type"("Simple"."Post_entity") RETURNS "Simple"."-ngs_Post_type-" AS $$ SELECT $1::text::"Simple"."-ngs_Post_type-" $$ IMMUTABLE LANGUAGE sql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_cast c JOIN pg_type s ON c.castsource = s.oid JOIN pg_type t ON c.casttarget = t.oid JOIN pg_namespace n ON n.oid = s.typnamespace AND n.oid = t.typnamespace
					WHERE n.nspname = 'Simple' AND s.typname = 'Post_entity' AND t.typname = '-ngs_Post_type-') THEN
		CREATE CAST ("Simple"."-ngs_Post_type-" AS "Simple"."Post_entity") WITH FUNCTION "Simple"."cast_Post_to_type"("Simple"."-ngs_Post_type-") AS IMPLICIT;
		CREATE CAST ("Simple"."Post_entity" AS "Simple"."-ngs_Post_type-") WITH FUNCTION "Simple"."cast_Post_to_type"("Simple"."Post_entity") AS IMPLICIT;
	END IF;
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION "Simple"."insert_Post"(IN _inserted "Simple"."Post_entity"[]) RETURNS VOID AS
$$
BEGIN
	INSERT INTO "Simple"."Post" ("id", "title", "created") VALUES(_inserted[1]."id", _inserted[1]."title", _inserted[1]."created");
	
END
$$
LANGUAGE plpgsql SECURITY DEFINER;;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'Simple' AND type_name = '>update-Post-pair<' AND column_name = 'original') THEN
		DROP TYPE IF EXISTS "Simple".">update-Post-pair<";
		CREATE TYPE "Simple".">update-Post-pair<" AS (original "Simple"."Post_entity", changed "Simple"."Post_entity");
	END IF;
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION "Simple"."persist_Post"(
IN _inserted "Simple"."Post_entity"[], IN _updated "Simple".">update-Post-pair<"[], IN _deleted "Simple"."Post_entity"[]) 
	RETURNS VARCHAR AS
$$
DECLARE cnt int;
DECLARE uri VARCHAR;
DECLARE tmp record;
DECLARE _update_count int = array_upper(_updated, 1);
DECLARE _delete_count int = array_upper(_deleted, 1);

BEGIN

	SET CONSTRAINTS ALL DEFERRED;

	

	INSERT INTO "Simple"."Post" ("id", "title", "created")
	SELECT _i."id", _i."title", _i."created" 
	FROM unnest(_inserted) _i;

	

	UPDATE "Simple"."Post" as _tbl SET "id" = (_u.changed)."id", "title" = (_u.changed)."title", "created" = (_u.changed)."created"
	FROM unnest(_updated) _u
	WHERE _tbl."id" = (_u.original)."id";

	GET DIAGNOSTICS cnt = ROW_COUNT;
	IF cnt != _update_count THEN 
		RETURN 'Updated ' || cnt || ' row(s). Expected to update ' || _update_count || ' row(s).';
	END IF;

	

	DELETE FROM "Simple"."Post"
	WHERE ("id") IN (SELECT _d."id" FROM unnest(_deleted) _d);

	GET DIAGNOSTICS cnt = ROW_COUNT;
	IF cnt != _delete_count THEN 
		RETURN 'Deleted ' || cnt || ' row(s). Expected to delete ' || _delete_count || ' row(s).';
	END IF;

	

	SET CONSTRAINTS ALL IMMEDIATE;

	RETURN NULL;
END
$$
LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION "Simple"."update_Post"(IN _original "Simple"."Post_entity"[], IN _updated "Simple"."Post_entity"[]) RETURNS VARCHAR AS
$$
BEGIN
	
	UPDATE "Simple"."Post" AS _tab SET "id" = _updated[1]."id", "title" = _updated[1]."title", "created" = _updated[1]."created" WHERE _tab."id" = _original[1]."id";
	
	RETURN NULL;
END
$$
LANGUAGE plpgsql SECURITY DEFINER;;

CREATE OR REPLACE VIEW "Simple"."Post_unprocessed_events" AS
SELECT _aggregate."id"
FROM
	"Simple"."Post_entity" _aggregate
;
COMMENT ON VIEW "Simple"."Post_unprocessed_events" IS 'NGS volatile';

CREATE OR REPLACE FUNCTION "StandardObjects"."cast_Invoice_to_type"("StandardObjects"."-ngs_Invoice_type-") RETURNS "StandardObjects"."Invoice_entity" AS $$ SELECT $1::text::"StandardObjects"."Invoice_entity" $$ IMMUTABLE LANGUAGE sql;
CREATE OR REPLACE FUNCTION "StandardObjects"."cast_Invoice_to_type"("StandardObjects"."Invoice_entity") RETURNS "StandardObjects"."-ngs_Invoice_type-" AS $$ SELECT $1::text::"StandardObjects"."-ngs_Invoice_type-" $$ IMMUTABLE LANGUAGE sql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_cast c JOIN pg_type s ON c.castsource = s.oid JOIN pg_type t ON c.casttarget = t.oid JOIN pg_namespace n ON n.oid = s.typnamespace AND n.oid = t.typnamespace
					WHERE n.nspname = 'StandardObjects' AND s.typname = 'Invoice_entity' AND t.typname = '-ngs_Invoice_type-') THEN
		CREATE CAST ("StandardObjects"."-ngs_Invoice_type-" AS "StandardObjects"."Invoice_entity") WITH FUNCTION "StandardObjects"."cast_Invoice_to_type"("StandardObjects"."-ngs_Invoice_type-") AS IMPLICIT;
		CREATE CAST ("StandardObjects"."Invoice_entity" AS "StandardObjects"."-ngs_Invoice_type-") WITH FUNCTION "StandardObjects"."cast_Invoice_to_type"("StandardObjects"."Invoice_entity") AS IMPLICIT;
	END IF;
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION "StandardObjects"."insert_Invoice"(IN _inserted "StandardObjects"."Invoice_entity"[]) RETURNS VOID AS
$$
BEGIN
	INSERT INTO "StandardObjects"."Invoice" ("number", "items", "dueDate", "total", "paid", "canceled", "version", "tax", "reference", "createdAt", "modifiedAt") VALUES(_inserted[1]."number", _inserted[1]."items", _inserted[1]."dueDate", _inserted[1]."total", _inserted[1]."paid", _inserted[1]."canceled", _inserted[1]."version", _inserted[1]."tax", _inserted[1]."reference", _inserted[1]."createdAt", _inserted[1]."modifiedAt");
	
END
$$
LANGUAGE plpgsql SECURITY DEFINER;;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardObjects' AND type_name = '>update-Invoice-pair<' AND column_name = 'original') THEN
		DROP TYPE IF EXISTS "StandardObjects".">update-Invoice-pair<";
		CREATE TYPE "StandardObjects".">update-Invoice-pair<" AS (original "StandardObjects"."Invoice_entity", changed "StandardObjects"."Invoice_entity");
	END IF;
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION "StandardObjects"."persist_Invoice"(
IN _inserted "StandardObjects"."Invoice_entity"[], IN _updated "StandardObjects".">update-Invoice-pair<"[], IN _deleted "StandardObjects"."Invoice_entity"[]) 
	RETURNS VARCHAR AS
$$
DECLARE cnt int;
DECLARE uri VARCHAR;
DECLARE tmp record;
DECLARE _update_count int = array_upper(_updated, 1);
DECLARE _delete_count int = array_upper(_deleted, 1);

BEGIN

	SET CONSTRAINTS ALL DEFERRED;

	

	INSERT INTO "StandardObjects"."Invoice" ("number", "items", "dueDate", "total", "paid", "canceled", "version", "tax", "reference", "createdAt", "modifiedAt")
	SELECT _i."number", _i."items", _i."dueDate", _i."total", _i."paid", _i."canceled", _i."version", _i."tax", _i."reference", _i."createdAt", _i."modifiedAt" 
	FROM unnest(_inserted) _i;

	

	UPDATE "StandardObjects"."Invoice" as _tbl SET "number" = (_u.changed)."number", "items" = (_u.changed)."items", "dueDate" = (_u.changed)."dueDate", "total" = (_u.changed)."total", "paid" = (_u.changed)."paid", "canceled" = (_u.changed)."canceled", "version" = (_u.changed)."version", "tax" = (_u.changed)."tax", "reference" = (_u.changed)."reference", "createdAt" = (_u.changed)."createdAt", "modifiedAt" = (_u.changed)."modifiedAt"
	FROM unnest(_updated) _u
	WHERE _tbl."number" = (_u.original)."number";

	GET DIAGNOSTICS cnt = ROW_COUNT;
	IF cnt != _update_count THEN 
		RETURN 'Updated ' || cnt || ' row(s). Expected to update ' || _update_count || ' row(s).';
	END IF;

	

	DELETE FROM "StandardObjects"."Invoice"
	WHERE ("number") IN (SELECT _d."number" FROM unnest(_deleted) _d);

	GET DIAGNOSTICS cnt = ROW_COUNT;
	IF cnt != _delete_count THEN 
		RETURN 'Deleted ' || cnt || ' row(s). Expected to delete ' || _delete_count || ' row(s).';
	END IF;

	

	SET CONSTRAINTS ALL IMMEDIATE;

	RETURN NULL;
END
$$
LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION "StandardObjects"."update_Invoice"(IN _original "StandardObjects"."Invoice_entity"[], IN _updated "StandardObjects"."Invoice_entity"[]) RETURNS VARCHAR AS
$$
BEGIN
	
	UPDATE "StandardObjects"."Invoice" AS _tab SET "number" = _updated[1]."number", "items" = _updated[1]."items", "dueDate" = _updated[1]."dueDate", "total" = _updated[1]."total", "paid" = _updated[1]."paid", "canceled" = _updated[1]."canceled", "version" = _updated[1]."version", "tax" = _updated[1]."tax", "reference" = _updated[1]."reference", "createdAt" = _updated[1]."createdAt", "modifiedAt" = _updated[1]."modifiedAt" WHERE _tab."number" = _original[1]."number";
	
	RETURN NULL;
END
$$
LANGUAGE plpgsql SECURITY DEFINER;;

CREATE OR REPLACE VIEW "StandardObjects"."Invoice_unprocessed_events" AS
SELECT _aggregate."number"
FROM
	"StandardObjects"."Invoice_entity" _aggregate
;
COMMENT ON VIEW "StandardObjects"."Invoice_unprocessed_events" IS 'NGS volatile';

CREATE OR REPLACE FUNCTION "StandardRelations"."cast_Item_to_type"("StandardRelations"."-ngs_Item_type-") RETURNS "StandardRelations"."Item_entity" AS $$ SELECT $1::text::"StandardRelations"."Item_entity" $$ IMMUTABLE LANGUAGE sql;
CREATE OR REPLACE FUNCTION "StandardRelations"."cast_Item_to_type"("StandardRelations"."Item_entity") RETURNS "StandardRelations"."-ngs_Item_type-" AS $$ SELECT $1::text::"StandardRelations"."-ngs_Item_type-" $$ IMMUTABLE LANGUAGE sql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_cast c JOIN pg_type s ON c.castsource = s.oid JOIN pg_type t ON c.casttarget = t.oid JOIN pg_namespace n ON n.oid = s.typnamespace AND n.oid = t.typnamespace
					WHERE n.nspname = 'StandardRelations' AND s.typname = 'Item_entity' AND t.typname = '-ngs_Item_type-') THEN
		CREATE CAST ("StandardRelations"."-ngs_Item_type-" AS "StandardRelations"."Item_entity") WITH FUNCTION "StandardRelations"."cast_Item_to_type"("StandardRelations"."-ngs_Item_type-") AS IMPLICIT;
		CREATE CAST ("StandardRelations"."Item_entity" AS "StandardRelations"."-ngs_Item_type-") WITH FUNCTION "StandardRelations"."cast_Item_to_type"("StandardRelations"."Item_entity") AS IMPLICIT;
	END IF;
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION "ComplexRelations"."cast_Account_to_type"("ComplexRelations"."-ngs_Account_type-") RETURNS "ComplexRelations"."Account_entity" AS $$ SELECT $1::text::"ComplexRelations"."Account_entity" $$ IMMUTABLE LANGUAGE sql;
CREATE OR REPLACE FUNCTION "ComplexRelations"."cast_Account_to_type"("ComplexRelations"."Account_entity") RETURNS "ComplexRelations"."-ngs_Account_type-" AS $$ SELECT $1::text::"ComplexRelations"."-ngs_Account_type-" $$ IMMUTABLE LANGUAGE sql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_cast c JOIN pg_type s ON c.castsource = s.oid JOIN pg_type t ON c.casttarget = t.oid JOIN pg_namespace n ON n.oid = s.typnamespace AND n.oid = t.typnamespace
					WHERE n.nspname = 'ComplexRelations' AND s.typname = 'Account_entity' AND t.typname = '-ngs_Account_type-') THEN
		CREATE CAST ("ComplexRelations"."-ngs_Account_type-" AS "ComplexRelations"."Account_entity") WITH FUNCTION "ComplexRelations"."cast_Account_to_type"("ComplexRelations"."-ngs_Account_type-") AS IMPLICIT;
		CREATE CAST ("ComplexRelations"."Account_entity" AS "ComplexRelations"."-ngs_Account_type-") WITH FUNCTION "ComplexRelations"."cast_Account_to_type"("ComplexRelations"."Account_entity") AS IMPLICIT;
	END IF;
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION "StandardRelations"."cast_Invoice_to_type"("StandardRelations"."-ngs_Invoice_type-") RETURNS "StandardRelations"."Invoice_entity" AS $$ SELECT $1::text::"StandardRelations"."Invoice_entity" $$ IMMUTABLE LANGUAGE sql;
CREATE OR REPLACE FUNCTION "StandardRelations"."cast_Invoice_to_type"("StandardRelations"."Invoice_entity") RETURNS "StandardRelations"."-ngs_Invoice_type-" AS $$ SELECT $1::text::"StandardRelations"."-ngs_Invoice_type-" $$ IMMUTABLE LANGUAGE sql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_cast c JOIN pg_type s ON c.castsource = s.oid JOIN pg_type t ON c.casttarget = t.oid JOIN pg_namespace n ON n.oid = s.typnamespace AND n.oid = t.typnamespace
					WHERE n.nspname = 'StandardRelations' AND s.typname = 'Invoice_entity' AND t.typname = '-ngs_Invoice_type-') THEN
		CREATE CAST ("StandardRelations"."-ngs_Invoice_type-" AS "StandardRelations"."Invoice_entity") WITH FUNCTION "StandardRelations"."cast_Invoice_to_type"("StandardRelations"."-ngs_Invoice_type-") AS IMPLICIT;
		CREATE CAST ("StandardRelations"."Invoice_entity" AS "StandardRelations"."-ngs_Invoice_type-") WITH FUNCTION "StandardRelations"."cast_Invoice_to_type"("StandardRelations"."Invoice_entity") AS IMPLICIT;
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardRelations' AND type_name = '>tmp-Invoice-insert<' AND column_name = 'tuple') THEN
		DROP TABLE IF EXISTS "StandardRelations".">tmp-Invoice-insert<";
	END IF;
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardRelations' AND type_name = '>tmp-Invoice-update<' AND column_name = 'old') THEN
		DROP TABLE IF EXISTS "StandardRelations".">tmp-Invoice-update<";
	END IF;
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardRelations' AND type_name = '>tmp-Invoice-delete<' AND column_name = 'tuple') THEN
		DROP TABLE IF EXISTS "StandardRelations".">tmp-Invoice-delete<";
	END IF;
	IF NOT EXISTS(SELECT * FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'StandardRelations' AND c.relname = '>tmp-Invoice-insert<') THEN
		CREATE UNLOGGED TABLE "StandardRelations".">tmp-Invoice-insert<" AS SELECT 0::int as i, t as tuple FROM "StandardRelations"."Invoice_entity" t LIMIT 0;
	END IF;
	IF NOT EXISTS(SELECT * FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'StandardRelations' AND c.relname = '>tmp-Invoice-update<') THEN
		CREATE UNLOGGED TABLE "StandardRelations".">tmp-Invoice-update<" AS SELECT 0::int as i, t as old, t as new FROM "StandardRelations"."Invoice_entity" t LIMIT 0;
	END IF;
	IF NOT EXISTS(SELECT * FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'StandardRelations' AND c.relname = '>tmp-Invoice-delete<') THEN
		CREATE UNLOGGED TABLE "StandardRelations".">tmp-Invoice-delete<" AS SELECT 0::int as i, t as tuple FROM "StandardRelations"."Invoice_entity" t LIMIT 0;
	END IF;

	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardRelations' AND type_name = '>tmp-Invoice-insert758996489<' AND column_name = 'tuple') THEN
		DROP TABLE IF EXISTS "StandardRelations".">tmp-Invoice-insert758996489<";
	END IF;
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardRelations' AND type_name = '>tmp-Invoice-update758996489<' AND column_name = 'old') THEN
		DROP TABLE IF EXISTS "StandardRelations".">tmp-Invoice-update758996489<";
	END IF;
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'StandardRelations' AND type_name = '>tmp-Invoice-delete758996489<' AND column_name = 'tuple') THEN
		DROP TABLE IF EXISTS "StandardRelations".">tmp-Invoice-delete758996489<";
	END IF;
	IF NOT EXISTS(SELECT * FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'StandardRelations' AND c.relname = '>tmp-Invoice-insert758996489<') THEN
		CREATE UNLOGGED TABLE "StandardRelations".">tmp-Invoice-insert758996489<" AS SELECT 0::int as i, 0::int as index, t as tuple FROM "StandardRelations"."Item_entity" t LIMIT 0;
	END IF;
	IF NOT EXISTS(SELECT * FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'StandardRelations' AND c.relname = '>tmp-Invoice-update758996489<') THEN
		CREATE UNLOGGED TABLE "StandardRelations".">tmp-Invoice-update758996489<" AS SELECT 0::int as i, 0::int as index, t as old, t as changed, t as new, true as is_new FROM "StandardRelations"."Item_entity" t LIMIT 0;
	END IF;
	IF NOT EXISTS(SELECT * FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'StandardRelations' AND c.relname = '>tmp-Invoice-delete758996489<') THEN
		CREATE UNLOGGED TABLE "StandardRelations".">tmp-Invoice-delete758996489<" AS SELECT 0::int as i, 0::int as index, t as tuple FROM "StandardRelations"."Item_entity" t LIMIT 0;
	END IF;
END $$ LANGUAGE plpgsql;

--TODO: temp fix for rename
DROP FUNCTION IF EXISTS "StandardRelations"."persist_Invoice_internal"(int, int);

CREATE OR REPLACE FUNCTION "StandardRelations"."persist_Invoice_internal"(_update_count int, _delete_count int) 
	RETURNS VARCHAR AS
$$
DECLARE cnt int;
DECLARE uri VARCHAR;
DECLARE tmp record;
DECLARE "_var_StandardRelations.Item" "StandardRelations"."Item_entity"[];
BEGIN

	SET CONSTRAINTS ALL DEFERRED;

	

	INSERT INTO "StandardRelations"."Invoice" ("number", "dueDate", "total", "paid", "canceled", "version", "tax", "reference", "createdAt", "modifiedAt")
	SELECT (tuple)."number", (tuple)."dueDate", (tuple)."total", (tuple)."paid", (tuple)."canceled", (tuple)."version", (tuple)."tax", (tuple)."reference", (tuple)."createdAt", (tuple)."modifiedAt" 
	FROM "StandardRelations".">tmp-Invoice-insert<" i;

	
	INSERT INTO "StandardRelations"."Item" ("product", "cost", "quantity", "taxGroup", "discount", "Invoicenumber", "Index")
	SELECT (tuple)."product", (tuple)."cost", (tuple)."quantity", (tuple)."taxGroup", (tuple)."discount", (tuple)."Invoicenumber", (tuple)."Index" 
	FROM "StandardRelations".">tmp-Invoice-insert758996489<" t;

		
	UPDATE "StandardRelations"."Invoice" as tbl SET 
		"number" = (new)."number", "dueDate" = (new)."dueDate", "total" = (new)."total", "paid" = (new)."paid", "canceled" = (new)."canceled", "version" = (new)."version", "tax" = (new)."tax", "reference" = (new)."reference", "createdAt" = (new)."createdAt", "modifiedAt" = (new)."modifiedAt"
	FROM "StandardRelations".">tmp-Invoice-update<" u
	WHERE
		tbl."number" = (old)."number";

	GET DIAGNOSTICS cnt = ROW_COUNT;
	IF cnt != _update_count THEN 
		RETURN 'Updated ' || cnt || ' row(s). Expected to update ' || _update_count || ' row(s).';
	END IF;

	
	DELETE FROM "StandardRelations"."Item" AS tbl
	WHERE 
		("Invoicenumber", "Index") IN (SELECT (u.old)."Invoicenumber", (u.old)."Index" FROM "StandardRelations".">tmp-Invoice-update758996489<" u WHERE NOT u.old IS NULL AND u.changed IS NULL);

	UPDATE "StandardRelations"."Item" AS tbl SET
		"product" = (u.changed)."product", "cost" = (u.changed)."cost", "quantity" = (u.changed)."quantity", "taxGroup" = (u.changed)."taxGroup", "discount" = (u.changed)."discount", "Invoicenumber" = (u.changed)."Invoicenumber", "Index" = (u.changed)."Index"
	FROM "StandardRelations".">tmp-Invoice-update758996489<" u
	WHERE
		NOT u.changed IS NULL
		AND NOT u.old IS NULL
		AND u.old != u.changed
		AND tbl."Invoicenumber" = (u.old)."Invoicenumber" AND tbl."Index" = (u.old)."Index" ;

	INSERT INTO "StandardRelations"."Item" ("product", "cost", "quantity", "taxGroup", "discount", "Invoicenumber", "Index")
	SELECT (new)."product", (new)."cost", (new)."quantity", (new)."taxGroup", (new)."discount", (new)."Invoicenumber", (new)."Index"
	FROM 
		"StandardRelations".">tmp-Invoice-update758996489<" u
	WHERE u.is_new;
	DELETE FROM "StandardRelations"."Item"	WHERE ("Invoicenumber", "Index") IN (SELECT (tuple)."Invoicenumber", (tuple)."Index" FROM "StandardRelations".">tmp-Invoice-delete758996489<" d);

	DELETE FROM "StandardRelations"."Invoice"
	WHERE ("number") IN (SELECT (tuple)."number" FROM "StandardRelations".">tmp-Invoice-delete<" d);

	GET DIAGNOSTICS cnt = ROW_COUNT;
	IF cnt != _delete_count THEN 
		RETURN 'Deleted ' || cnt || ' row(s). Expected to delete ' || _delete_count || ' row(s).';
	END IF;

	

	SET CONSTRAINTS ALL IMMEDIATE;

	
	DELETE FROM "StandardRelations".">tmp-Invoice-insert758996489<";
	DELETE FROM "StandardRelations".">tmp-Invoice-update758996489<";
	DELETE FROM "StandardRelations".">tmp-Invoice-delete758996489<";
	DELETE FROM "StandardRelations".">tmp-Invoice-insert<";
	DELETE FROM "StandardRelations".">tmp-Invoice-update<";
	DELETE FROM "StandardRelations".">tmp-Invoice-delete<";

	RETURN NULL;
END
$$
LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION "StandardRelations"."persist_Invoice"(
IN _inserted "StandardRelations"."Invoice_entity"[], IN _updated_original "StandardRelations"."Invoice_entity"[], IN _updated_new "StandardRelations"."Invoice_entity"[], IN _deleted "StandardRelations"."Invoice_entity"[]) 
	RETURNS VARCHAR AS
$$
DECLARE cnt int;
DECLARE uri VARCHAR;
DECLARE tmp record;
DECLARE "_var_StandardRelations.Item" "StandardRelations"."Item_entity"[];
BEGIN

	INSERT INTO "StandardRelations".">tmp-Invoice-insert<"
	SELECT i, _inserted[i]
	FROM generate_series(1, array_upper(_inserted, 1)) i;

	INSERT INTO "StandardRelations".">tmp-Invoice-update<"
	SELECT i, _updated_original[i], _updated_new[i]
	FROM generate_series(1, array_upper(_updated_new, 1)) i;

	INSERT INTO "StandardRelations".">tmp-Invoice-delete<"
	SELECT i, _deleted[i]
	FROM generate_series(1, array_upper(_deleted, 1)) i;

	
	FOR cnt, "_var_StandardRelations.Item" IN SELECT t.i, (t.tuple)."items" AS children FROM "StandardRelations".">tmp-Invoice-insert<" t LOOP
		INSERT INTO "StandardRelations".">tmp-Invoice-insert758996489<"
		SELECT cnt, index, "_var_StandardRelations.Item"[index] from generate_series(1, array_upper("_var_StandardRelations.Item", 1)) index;
	END LOOP;

	INSERT INTO "StandardRelations".">tmp-Invoice-update758996489<"
	SELECT i, index, old[index] AS old, 
		case when old[index]."Invoicenumber" = new[index]."Invoicenumber" AND old[index]."Index" = new[index]."Index" then new[index] else (select n from unnest(new) n where n."Invoicenumber" = old[index]."Invoicenumber" AND n."Index" = old[index]."Index") end AS changed,
		new[index] AS new, 
		case when old[index]."Invoicenumber" = new[index]."Invoicenumber" AND old[index]."Index" = new[index]."Index" then false else not exists(select o from unnest(old) o where o."Invoicenumber" = new[index]."Invoicenumber" AND o."Index" = new[index]."Index") AND NOT new[index] IS NULL end as is_new
	FROM 
		(
			SELECT 
				i, 
				(t.old)."items" AS old,
				(t.new)."items" AS new,
				unnest((SELECT array_agg(i) FROM generate_series(1, CASE WHEN coalesce(array_upper((t.old)."items", 1), 0) > coalesce(array_upper((t.new)."items", 1),0) THEN array_upper((t.old)."items", 1) ELSE array_upper((t.new)."items", 1) END) i)) as index 
			FROM "StandardRelations".">tmp-Invoice-update<" t
			WHERE 
				NOT (t.old)."items" IS NULL AND (t.new)."items" IS NULL
				OR (t.old)."items" IS NULL AND NOT (t.new)."items" IS NULL
				OR NOT (t.old)."items" IS NULL AND NOT (t.new)."items" IS NULL AND (t.old)."items" != (t.new)."items"
		) sq;

	FOR cnt, "_var_StandardRelations.Item" IN SELECT t.i, (t.tuple)."items" AS children FROM "StandardRelations".">tmp-Invoice-delete<" t LOOP
		INSERT INTO "StandardRelations".">tmp-Invoice-delete758996489<"
		SELECT cnt, index, "_var_StandardRelations.Item"[index] from generate_series(1, array_upper("_var_StandardRelations.Item", 1)) index;
	END LOOP;

	RETURN "StandardRelations"."persist_Invoice_internal"(array_upper(_updated_new, 1), array_upper(_deleted, 1));
END
$$
LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE VIEW "StandardRelations"."Invoice_unprocessed_events" AS
SELECT _aggregate."number"
FROM
	"StandardRelations"."Invoice_entity" _aggregate
;
COMMENT ON VIEW "StandardRelations"."Invoice_unprocessed_events" IS 'NGS volatile';

CREATE OR REPLACE FUNCTION "ComplexRelations"."cast_BankScrape_to_type"("ComplexRelations"."-ngs_BankScrape_type-") RETURNS "ComplexRelations"."BankScrape_entity" AS $$ SELECT $1::text::"ComplexRelations"."BankScrape_entity" $$ IMMUTABLE LANGUAGE sql;
CREATE OR REPLACE FUNCTION "ComplexRelations"."cast_BankScrape_to_type"("ComplexRelations"."BankScrape_entity") RETURNS "ComplexRelations"."-ngs_BankScrape_type-" AS $$ SELECT $1::text::"ComplexRelations"."-ngs_BankScrape_type-" $$ IMMUTABLE LANGUAGE sql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_cast c JOIN pg_type s ON c.castsource = s.oid JOIN pg_type t ON c.casttarget = t.oid JOIN pg_namespace n ON n.oid = s.typnamespace AND n.oid = t.typnamespace
					WHERE n.nspname = 'ComplexRelations' AND s.typname = 'BankScrape_entity' AND t.typname = '-ngs_BankScrape_type-') THEN
		CREATE CAST ("ComplexRelations"."-ngs_BankScrape_type-" AS "ComplexRelations"."BankScrape_entity") WITH FUNCTION "ComplexRelations"."cast_BankScrape_to_type"("ComplexRelations"."-ngs_BankScrape_type-") AS IMPLICIT;
		CREATE CAST ("ComplexRelations"."BankScrape_entity" AS "ComplexRelations"."-ngs_BankScrape_type-") WITH FUNCTION "ComplexRelations"."cast_BankScrape_to_type"("ComplexRelations"."BankScrape_entity") AS IMPLICIT;
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = '>tmp-BankScrape-insert<' AND column_name = 'tuple') THEN
		DROP TABLE IF EXISTS "ComplexRelations".">tmp-BankScrape-insert<";
	END IF;
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = '>tmp-BankScrape-update<' AND column_name = 'old') THEN
		DROP TABLE IF EXISTS "ComplexRelations".">tmp-BankScrape-update<";
	END IF;
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = '>tmp-BankScrape-delete<' AND column_name = 'tuple') THEN
		DROP TABLE IF EXISTS "ComplexRelations".">tmp-BankScrape-delete<";
	END IF;
	IF NOT EXISTS(SELECT * FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'ComplexRelations' AND c.relname = '>tmp-BankScrape-insert<') THEN
		CREATE UNLOGGED TABLE "ComplexRelations".">tmp-BankScrape-insert<" AS SELECT 0::int as i, t as tuple FROM "ComplexRelations"."BankScrape_entity" t LIMIT 0;
	END IF;
	IF NOT EXISTS(SELECT * FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'ComplexRelations' AND c.relname = '>tmp-BankScrape-update<') THEN
		CREATE UNLOGGED TABLE "ComplexRelations".">tmp-BankScrape-update<" AS SELECT 0::int as i, t as old, t as new FROM "ComplexRelations"."BankScrape_entity" t LIMIT 0;
	END IF;
	IF NOT EXISTS(SELECT * FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'ComplexRelations' AND c.relname = '>tmp-BankScrape-delete<') THEN
		CREATE UNLOGGED TABLE "ComplexRelations".">tmp-BankScrape-delete<" AS SELECT 0::int as i, t as tuple FROM "ComplexRelations"."BankScrape_entity" t LIMIT 0;
	END IF;

	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = '>tmp-BankScrape-insert758926083<' AND column_name = 'tuple') THEN
		DROP TABLE IF EXISTS "ComplexRelations".">tmp-BankScrape-insert758926083<";
	END IF;
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = '>tmp-BankScrape-update758926083<' AND column_name = 'old') THEN
		DROP TABLE IF EXISTS "ComplexRelations".">tmp-BankScrape-update758926083<";
	END IF;
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = '>tmp-BankScrape-delete758926083<' AND column_name = 'tuple') THEN
		DROP TABLE IF EXISTS "ComplexRelations".">tmp-BankScrape-delete758926083<";
	END IF;
	IF NOT EXISTS(SELECT * FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'ComplexRelations' AND c.relname = '>tmp-BankScrape-insert758926083<') THEN
		CREATE UNLOGGED TABLE "ComplexRelations".">tmp-BankScrape-insert758926083<" AS SELECT 0::int as i, 0::int as index, t as tuple FROM "ComplexRelations"."Account_entity" t LIMIT 0;
	END IF;
	IF NOT EXISTS(SELECT * FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'ComplexRelations' AND c.relname = '>tmp-BankScrape-update758926083<') THEN
		CREATE UNLOGGED TABLE "ComplexRelations".">tmp-BankScrape-update758926083<" AS SELECT 0::int as i, 0::int as index, t as old, t as changed, t as new, true as is_new FROM "ComplexRelations"."Account_entity" t LIMIT 0;
	END IF;
	IF NOT EXISTS(SELECT * FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'ComplexRelations' AND c.relname = '>tmp-BankScrape-delete758926083<') THEN
		CREATE UNLOGGED TABLE "ComplexRelations".">tmp-BankScrape-delete758926083<" AS SELECT 0::int as i, 0::int as index, t as tuple FROM "ComplexRelations"."Account_entity" t LIMIT 0;
	END IF;
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = '>tmp-BankScrape-insert2081800870<' AND column_name = 'tuple') THEN
		DROP TABLE IF EXISTS "ComplexRelations".">tmp-BankScrape-insert2081800870<";
	END IF;
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = '>tmp-BankScrape-update2081800870<' AND column_name = 'old') THEN
		DROP TABLE IF EXISTS "ComplexRelations".">tmp-BankScrape-update2081800870<";
	END IF;
	IF NOT EXISTS(SELECT * FROM "-NGS-".Load_Type_Info() WHERE type_schema = 'ComplexRelations' AND type_name = '>tmp-BankScrape-delete2081800870<' AND column_name = 'tuple') THEN
		DROP TABLE IF EXISTS "ComplexRelations".">tmp-BankScrape-delete2081800870<";
	END IF;
	IF NOT EXISTS(SELECT * FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'ComplexRelations' AND c.relname = '>tmp-BankScrape-insert2081800870<') THEN
		CREATE UNLOGGED TABLE "ComplexRelations".">tmp-BankScrape-insert2081800870<" AS SELECT 0::int as i, 0::int as index, t as tuple FROM "ComplexRelations"."Transaction_entity" t LIMIT 0;
	END IF;
	IF NOT EXISTS(SELECT * FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'ComplexRelations' AND c.relname = '>tmp-BankScrape-update2081800870<') THEN
		CREATE UNLOGGED TABLE "ComplexRelations".">tmp-BankScrape-update2081800870<" AS SELECT 0::int as i, 0::int as index, t as old, t as changed, t as new, true as is_new FROM "ComplexRelations"."Transaction_entity" t LIMIT 0;
	END IF;
	IF NOT EXISTS(SELECT * FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'ComplexRelations' AND c.relname = '>tmp-BankScrape-delete2081800870<') THEN
		CREATE UNLOGGED TABLE "ComplexRelations".">tmp-BankScrape-delete2081800870<" AS SELECT 0::int as i, 0::int as index, t as tuple FROM "ComplexRelations"."Transaction_entity" t LIMIT 0;
	END IF;
END $$ LANGUAGE plpgsql;

--TODO: temp fix for rename
DROP FUNCTION IF EXISTS "ComplexRelations"."persist_BankScrape_internal"(int, int);

CREATE OR REPLACE FUNCTION "ComplexRelations"."persist_BankScrape_internal"(_update_count int, _delete_count int) 
	RETURNS VARCHAR AS
$$
DECLARE cnt int;
DECLARE uri VARCHAR;
DECLARE tmp record;
DECLARE "_var_ComplexRelations.Account" "ComplexRelations"."Account_entity"[];
DECLARE "_var_ComplexRelations.Transaction" "ComplexRelations"."Transaction_entity"[];
BEGIN

	SET CONSTRAINTS ALL DEFERRED;

	

	INSERT INTO "ComplexRelations"."BankScrape" ("id", "website", "at", "info", "externalId", "ranking", "tags", "createdAt")
	SELECT (tuple)."id", (tuple)."website", (tuple)."at", (tuple)."info", (tuple)."externalId", (tuple)."ranking", (tuple)."tags", (tuple)."createdAt" 
	FROM "ComplexRelations".">tmp-BankScrape-insert<" i;

	
	INSERT INTO "ComplexRelations"."Account" ("balance", "number", "name", "notes", "BankScrapeid", "Index")
	SELECT (tuple)."balance", (tuple)."number", (tuple)."name", (tuple)."notes", (tuple)."BankScrapeid", (tuple)."Index" 
	FROM "ComplexRelations".">tmp-BankScrape-insert758926083<" t;
	INSERT INTO "ComplexRelations"."Transaction" ("date", "description", "currency", "amount", "AccountBankScrapeid", "AccountIndex", "Index")
	SELECT (tuple)."date", (tuple)."description", (tuple)."currency", (tuple)."amount", (tuple)."AccountBankScrapeid", (tuple)."AccountIndex", (tuple)."Index" 
	FROM "ComplexRelations".">tmp-BankScrape-insert2081800870<" t;

		
	UPDATE "ComplexRelations"."BankScrape" as tbl SET 
		"id" = (new)."id", "website" = (new)."website", "at" = (new)."at", "info" = (new)."info", "externalId" = (new)."externalId", "ranking" = (new)."ranking", "tags" = (new)."tags", "createdAt" = (new)."createdAt"
	FROM "ComplexRelations".">tmp-BankScrape-update<" u
	WHERE
		tbl."id" = (old)."id";

	GET DIAGNOSTICS cnt = ROW_COUNT;
	IF cnt != _update_count THEN 
		RETURN 'Updated ' || cnt || ' row(s). Expected to update ' || _update_count || ' row(s).';
	END IF;

	
	DELETE FROM "ComplexRelations"."Account" AS tbl
	WHERE 
		("BankScrapeid", "Index") IN (SELECT (u.old)."BankScrapeid", (u.old)."Index" FROM "ComplexRelations".">tmp-BankScrape-update758926083<" u WHERE NOT u.old IS NULL AND u.changed IS NULL);

	UPDATE "ComplexRelations"."Account" AS tbl SET
		"balance" = (u.changed)."balance", "number" = (u.changed)."number", "name" = (u.changed)."name", "notes" = (u.changed)."notes", "BankScrapeid" = (u.changed)."BankScrapeid", "Index" = (u.changed)."Index"
	FROM "ComplexRelations".">tmp-BankScrape-update758926083<" u
	WHERE
		NOT u.changed IS NULL
		AND NOT u.old IS NULL
		AND u.old != u.changed
		AND tbl."BankScrapeid" = (u.old)."BankScrapeid" AND tbl."Index" = (u.old)."Index" ;

	INSERT INTO "ComplexRelations"."Account" ("balance", "number", "name", "notes", "BankScrapeid", "Index")
	SELECT (new)."balance", (new)."number", (new)."name", (new)."notes", (new)."BankScrapeid", (new)."Index"
	FROM 
		"ComplexRelations".">tmp-BankScrape-update758926083<" u
	WHERE u.is_new;
	DELETE FROM "ComplexRelations"."Transaction" AS tbl
	WHERE 
		("AccountBankScrapeid", "AccountIndex", "Index") IN (SELECT (u.old)."AccountBankScrapeid", (u.old)."AccountIndex", (u.old)."Index" FROM "ComplexRelations".">tmp-BankScrape-update2081800870<" u WHERE NOT u.old IS NULL AND u.changed IS NULL);

	UPDATE "ComplexRelations"."Transaction" AS tbl SET
		"date" = (u.changed)."date", "description" = (u.changed)."description", "currency" = (u.changed)."currency", "amount" = (u.changed)."amount", "AccountBankScrapeid" = (u.changed)."AccountBankScrapeid", "AccountIndex" = (u.changed)."AccountIndex", "Index" = (u.changed)."Index"
	FROM "ComplexRelations".">tmp-BankScrape-update2081800870<" u
	WHERE
		NOT u.changed IS NULL
		AND NOT u.old IS NULL
		AND u.old != u.changed
		AND tbl."AccountBankScrapeid" = (u.old)."AccountBankScrapeid" AND tbl."AccountIndex" = (u.old)."AccountIndex" AND tbl."Index" = (u.old)."Index" ;

	INSERT INTO "ComplexRelations"."Transaction" ("date", "description", "currency", "amount", "AccountBankScrapeid", "AccountIndex", "Index")
	SELECT (new)."date", (new)."description", (new)."currency", (new)."amount", (new)."AccountBankScrapeid", (new)."AccountIndex", (new)."Index"
	FROM 
		"ComplexRelations".">tmp-BankScrape-update2081800870<" u
	WHERE u.is_new;
	DELETE FROM "ComplexRelations"."Account"	WHERE ("BankScrapeid", "Index") IN (SELECT (tuple)."BankScrapeid", (tuple)."Index" FROM "ComplexRelations".">tmp-BankScrape-delete758926083<" d);
	DELETE FROM "ComplexRelations"."Transaction"	WHERE ("AccountBankScrapeid", "AccountIndex", "Index") IN (SELECT (tuple)."AccountBankScrapeid", (tuple)."AccountIndex", (tuple)."Index" FROM "ComplexRelations".">tmp-BankScrape-delete2081800870<" d);

	DELETE FROM "ComplexRelations"."BankScrape"
	WHERE ("id") IN (SELECT (tuple)."id" FROM "ComplexRelations".">tmp-BankScrape-delete<" d);

	GET DIAGNOSTICS cnt = ROW_COUNT;
	IF cnt != _delete_count THEN 
		RETURN 'Deleted ' || cnt || ' row(s). Expected to delete ' || _delete_count || ' row(s).';
	END IF;

	

	SET CONSTRAINTS ALL IMMEDIATE;

	
	DELETE FROM "ComplexRelations".">tmp-BankScrape-insert758926083<";
	DELETE FROM "ComplexRelations".">tmp-BankScrape-update758926083<";
	DELETE FROM "ComplexRelations".">tmp-BankScrape-delete758926083<";
	DELETE FROM "ComplexRelations".">tmp-BankScrape-insert2081800870<";
	DELETE FROM "ComplexRelations".">tmp-BankScrape-update2081800870<";
	DELETE FROM "ComplexRelations".">tmp-BankScrape-delete2081800870<";
	DELETE FROM "ComplexRelations".">tmp-BankScrape-insert<";
	DELETE FROM "ComplexRelations".">tmp-BankScrape-update<";
	DELETE FROM "ComplexRelations".">tmp-BankScrape-delete<";

	RETURN NULL;
END
$$
LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION "ComplexRelations"."persist_BankScrape"(
IN _inserted "ComplexRelations"."BankScrape_entity"[], IN _updated_original "ComplexRelations"."BankScrape_entity"[], IN _updated_new "ComplexRelations"."BankScrape_entity"[], IN _deleted "ComplexRelations"."BankScrape_entity"[]) 
	RETURNS VARCHAR AS
$$
DECLARE cnt int;
DECLARE uri VARCHAR;
DECLARE tmp record;
DECLARE "_var_ComplexRelations.Account" "ComplexRelations"."Account_entity"[];
DECLARE "_var_ComplexRelations.Transaction" "ComplexRelations"."Transaction_entity"[];
BEGIN

	INSERT INTO "ComplexRelations".">tmp-BankScrape-insert<"
	SELECT i, _inserted[i]
	FROM generate_series(1, array_upper(_inserted, 1)) i;

	INSERT INTO "ComplexRelations".">tmp-BankScrape-update<"
	SELECT i, _updated_original[i], _updated_new[i]
	FROM generate_series(1, array_upper(_updated_new, 1)) i;

	INSERT INTO "ComplexRelations".">tmp-BankScrape-delete<"
	SELECT i, _deleted[i]
	FROM generate_series(1, array_upper(_deleted, 1)) i;

	
	FOR cnt, "_var_ComplexRelations.Account" IN SELECT t.i, (t.tuple)."accounts" AS children FROM "ComplexRelations".">tmp-BankScrape-insert<" t LOOP
		INSERT INTO "ComplexRelations".">tmp-BankScrape-insert758926083<"
		SELECT cnt, index, "_var_ComplexRelations.Account"[index] from generate_series(1, array_upper("_var_ComplexRelations.Account", 1)) index;
	END LOOP;

	INSERT INTO "ComplexRelations".">tmp-BankScrape-update758926083<"
	SELECT i, index, old[index] AS old, 
		case when old[index]."BankScrapeid" = new[index]."BankScrapeid" AND old[index]."Index" = new[index]."Index" then new[index] else (select n from unnest(new) n where n."BankScrapeid" = old[index]."BankScrapeid" AND n."Index" = old[index]."Index") end AS changed,
		new[index] AS new, 
		case when old[index]."BankScrapeid" = new[index]."BankScrapeid" AND old[index]."Index" = new[index]."Index" then false else not exists(select o from unnest(old) o where o."BankScrapeid" = new[index]."BankScrapeid" AND o."Index" = new[index]."Index") AND NOT new[index] IS NULL end as is_new
	FROM 
		(
			SELECT 
				i, 
				(t.old)."accounts" AS old,
				(t.new)."accounts" AS new,
				unnest((SELECT array_agg(i) FROM generate_series(1, CASE WHEN coalesce(array_upper((t.old)."accounts", 1), 0) > coalesce(array_upper((t.new)."accounts", 1),0) THEN array_upper((t.old)."accounts", 1) ELSE array_upper((t.new)."accounts", 1) END) i)) as index 
			FROM "ComplexRelations".">tmp-BankScrape-update<" t
			WHERE 
				NOT (t.old)."accounts" IS NULL AND (t.new)."accounts" IS NULL
				OR (t.old)."accounts" IS NULL AND NOT (t.new)."accounts" IS NULL
				OR NOT (t.old)."accounts" IS NULL AND NOT (t.new)."accounts" IS NULL AND (t.old)."accounts" != (t.new)."accounts"
		) sq;

	FOR cnt, "_var_ComplexRelations.Account" IN SELECT t.i, (t.tuple)."accounts" AS children FROM "ComplexRelations".">tmp-BankScrape-delete<" t LOOP
		INSERT INTO "ComplexRelations".">tmp-BankScrape-delete758926083<"
		SELECT cnt, index, "_var_ComplexRelations.Account"[index] from generate_series(1, array_upper("_var_ComplexRelations.Account", 1)) index;
	END LOOP;
	FOR cnt, "_var_ComplexRelations.Transaction" IN SELECT t.i, (t.tuple)."transactions" AS children FROM "ComplexRelations".">tmp-BankScrape-insert758926083<" t LOOP
		INSERT INTO "ComplexRelations".">tmp-BankScrape-insert2081800870<"
		SELECT cnt, index, "_var_ComplexRelations.Transaction"[index] from generate_series(1, array_upper("_var_ComplexRelations.Transaction", 1)) index;
	END LOOP;

	INSERT INTO "ComplexRelations".">tmp-BankScrape-update2081800870<"
	SELECT i, index, old[index] AS old, 
		case when old[index]."AccountBankScrapeid" = new[index]."AccountBankScrapeid" AND old[index]."AccountIndex" = new[index]."AccountIndex" AND old[index]."Index" = new[index]."Index" then new[index] else (select n from unnest(new) n where n."AccountBankScrapeid" = old[index]."AccountBankScrapeid" AND n."AccountIndex" = old[index]."AccountIndex" AND n."Index" = old[index]."Index") end AS changed,
		new[index] AS new, 
		case when old[index]."AccountBankScrapeid" = new[index]."AccountBankScrapeid" AND old[index]."AccountIndex" = new[index]."AccountIndex" AND old[index]."Index" = new[index]."Index" then false else not exists(select o from unnest(old) o where o."AccountBankScrapeid" = new[index]."AccountBankScrapeid" AND o."AccountIndex" = new[index]."AccountIndex" AND o."Index" = new[index]."Index") AND NOT new[index] IS NULL end as is_new
	FROM 
		(
			SELECT 
				i, 
				(t.old)."transactions" AS old,
				(t.new)."transactions" AS new,
				unnest((SELECT array_agg(i) FROM generate_series(1, CASE WHEN coalesce(array_upper((t.old)."transactions", 1), 0) > coalesce(array_upper((t.new)."transactions", 1),0) THEN array_upper((t.old)."transactions", 1) ELSE array_upper((t.new)."transactions", 1) END) i)) as index 
			FROM "ComplexRelations".">tmp-BankScrape-update758926083<" t
			WHERE 
				NOT (t.old)."transactions" IS NULL AND (t.new)."transactions" IS NULL
				OR (t.old)."transactions" IS NULL AND NOT (t.new)."transactions" IS NULL
				OR NOT (t.old)."transactions" IS NULL AND NOT (t.new)."transactions" IS NULL AND (t.old)."transactions" != (t.new)."transactions"
		) sq;

	FOR cnt, "_var_ComplexRelations.Transaction" IN SELECT t.i, (t.tuple)."transactions" AS children FROM "ComplexRelations".">tmp-BankScrape-delete758926083<" t LOOP
		INSERT INTO "ComplexRelations".">tmp-BankScrape-delete2081800870<"
		SELECT cnt, index, "_var_ComplexRelations.Transaction"[index] from generate_series(1, array_upper("_var_ComplexRelations.Transaction", 1)) index;
	END LOOP;

	RETURN "ComplexRelations"."persist_BankScrape_internal"(array_upper(_updated_new, 1), array_upper(_deleted, 1));
END
$$
LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE VIEW "ComplexRelations"."BankScrape_unprocessed_events" AS
SELECT _aggregate."id"
FROM
	"ComplexRelations"."BankScrape_entity" _aggregate
;
COMMENT ON VIEW "ComplexRelations"."BankScrape_unprocessed_events" IS 'NGS volatile';

SELECT "-NGS-".Create_Type_Cast('"Complex"."cast_BankScrape_to_type"("Complex"."-ngs_BankScrape_type-")', 'Complex', '-ngs_BankScrape_type-', 'BankScrape');
SELECT "-NGS-".Create_Type_Cast('"Complex"."cast_BankScrape_to_type"("Complex"."BankScrape")', 'Complex', 'BankScrape', '-ngs_BankScrape_type-');

SELECT "-NGS-".Create_Type_Cast('"ComplexObjects"."cast_Account_to_type"("ComplexObjects"."-ngs_Account_type-")', 'ComplexObjects', '-ngs_Account_type-', 'Account');
SELECT "-NGS-".Create_Type_Cast('"ComplexObjects"."cast_Account_to_type"("ComplexObjects"."Account")', 'ComplexObjects', 'Account', '-ngs_Account_type-');

SELECT "-NGS-".Create_Type_Cast('"ComplexObjects"."cast_Transaction_to_type"("ComplexObjects"."-ngs_Transaction_type-")', 'ComplexObjects', '-ngs_Transaction_type-', 'Transaction');
SELECT "-NGS-".Create_Type_Cast('"ComplexObjects"."cast_Transaction_to_type"("ComplexObjects"."Transaction")', 'ComplexObjects', 'Transaction', '-ngs_Transaction_type-');

SELECT "-NGS-".Create_Type_Cast('"Standard"."cast_Invoice_to_type"("Standard"."-ngs_Invoice_type-")', 'Standard', '-ngs_Invoice_type-', 'Invoice');
SELECT "-NGS-".Create_Type_Cast('"Standard"."cast_Invoice_to_type"("Standard"."Invoice")', 'Standard', 'Invoice', '-ngs_Invoice_type-');

SELECT "-NGS-".Create_Type_Cast('"StandardObjects"."cast_Item_to_type"("StandardObjects"."-ngs_Item_type-")', 'StandardObjects', '-ngs_Item_type-', 'Item');
SELECT "-NGS-".Create_Type_Cast('"StandardObjects"."cast_Item_to_type"("StandardObjects"."Item")', 'StandardObjects', 'Item', '-ngs_Item_type-');

SELECT "-NGS-".Create_Type_Cast('"ComplexObjects"."cast_BankScrape_to_type"("ComplexObjects"."-ngs_BankScrape_type-")', 'ComplexObjects', '-ngs_BankScrape_type-', 'BankScrape_entity');
SELECT "-NGS-".Create_Type_Cast('"ComplexObjects"."cast_BankScrape_to_type"("ComplexObjects"."BankScrape_entity")', 'ComplexObjects', 'BankScrape_entity', '-ngs_BankScrape_type-');
CREATE OR REPLACE FUNCTION "ComplexObjects"."BankScrape.FindBy"("it" "ComplexObjects"."BankScrape_entity", "start" TIMESTAMPTZ, "end" TIMESTAMPTZ) RETURNS BOOL AS 
$$
	SELECT 	 ( ((("it"))."createdAt" >= "BankScrape.FindBy"."start") AND  ((("it"))."createdAt" <= "BankScrape.FindBy"."end")) 
$$ LANGUAGE SQL IMMUTABLE SECURITY DEFINER;
CREATE OR REPLACE FUNCTION "ComplexObjects"."BankScrape.FindBy"("start" TIMESTAMPTZ, "end" TIMESTAMPTZ) RETURNS SETOF "ComplexObjects"."BankScrape_entity" AS 
$$SELECT * FROM "ComplexObjects"."BankScrape_entity" "it"  WHERE 	 ( ((("it"))."createdAt" >= "BankScrape.FindBy"."start") AND  ((("it"))."createdAt" <= "BankScrape.FindBy"."end")) 
$$ LANGUAGE SQL STABLE SECURITY DEFINER;

SELECT "-NGS-".Create_Type_Cast('"ComplexRelations"."cast_Transaction_to_type"("ComplexRelations"."-ngs_Transaction_type-")', 'ComplexRelations', '-ngs_Transaction_type-', 'Transaction_entity');
SELECT "-NGS-".Create_Type_Cast('"ComplexRelations"."cast_Transaction_to_type"("ComplexRelations"."Transaction_entity")', 'ComplexRelations', 'Transaction_entity', '-ngs_Transaction_type-');

SELECT "-NGS-".Create_Type_Cast('"Simple"."cast_Post_to_type"("Simple"."-ngs_Post_type-")', 'Simple', '-ngs_Post_type-', 'Post_entity');
SELECT "-NGS-".Create_Type_Cast('"Simple"."cast_Post_to_type"("Simple"."Post_entity")', 'Simple', 'Post_entity', '-ngs_Post_type-');
CREATE OR REPLACE FUNCTION "Simple"."Post.FindBy"("it" "Simple"."Post_entity", "start" DATE, "end" DATE) RETURNS BOOL AS 
$$
	SELECT 	 ( ((("it"))."created" >= "Post.FindBy"."start") AND  ((("it"))."created" <= "Post.FindBy"."end")) 
$$ LANGUAGE SQL IMMUTABLE SECURITY DEFINER;
CREATE OR REPLACE FUNCTION "Simple"."Post.FindBy"("start" DATE, "end" DATE) RETURNS SETOF "Simple"."Post_entity" AS 
$$SELECT * FROM "Simple"."Post_entity" "it"  WHERE 	 ( ((("it"))."created" >= "Post.FindBy"."start") AND  ((("it"))."created" <= "Post.FindBy"."end")) 
$$ LANGUAGE SQL STABLE SECURITY DEFINER;

SELECT "-NGS-".Create_Type_Cast('"StandardObjects"."cast_Invoice_to_type"("StandardObjects"."-ngs_Invoice_type-")', 'StandardObjects', '-ngs_Invoice_type-', 'Invoice_entity');
SELECT "-NGS-".Create_Type_Cast('"StandardObjects"."cast_Invoice_to_type"("StandardObjects"."Invoice_entity")', 'StandardObjects', 'Invoice_entity', '-ngs_Invoice_type-');
CREATE OR REPLACE FUNCTION "StandardObjects"."Invoice.FindBy"("it" "StandardObjects"."Invoice_entity", "start" INT, "end" INT) RETURNS BOOL AS 
$$
	SELECT 	 ( ((("it"))."version" >= "Invoice.FindBy"."start") AND  ((("it"))."version" <= "Invoice.FindBy"."end")) 
$$ LANGUAGE SQL IMMUTABLE SECURITY DEFINER;
CREATE OR REPLACE FUNCTION "StandardObjects"."Invoice.FindBy"("start" INT, "end" INT) RETURNS SETOF "StandardObjects"."Invoice_entity" AS 
$$SELECT * FROM "StandardObjects"."Invoice_entity" "it"  WHERE 	 ( ((("it"))."version" >= "Invoice.FindBy"."start") AND  ((("it"))."version" <= "Invoice.FindBy"."end")) 
$$ LANGUAGE SQL STABLE SECURITY DEFINER;

SELECT "-NGS-".Create_Type_Cast('"StandardRelations"."cast_Item_to_type"("StandardRelations"."-ngs_Item_type-")', 'StandardRelations', '-ngs_Item_type-', 'Item_entity');
SELECT "-NGS-".Create_Type_Cast('"StandardRelations"."cast_Item_to_type"("StandardRelations"."Item_entity")', 'StandardRelations', 'Item_entity', '-ngs_Item_type-');

SELECT "-NGS-".Create_Type_Cast('"ComplexRelations"."cast_Account_to_type"("ComplexRelations"."-ngs_Account_type-")', 'ComplexRelations', '-ngs_Account_type-', 'Account_entity');
SELECT "-NGS-".Create_Type_Cast('"ComplexRelations"."cast_Account_to_type"("ComplexRelations"."Account_entity")', 'ComplexRelations', 'Account_entity', '-ngs_Account_type-');

SELECT "-NGS-".Create_Type_Cast('"StandardRelations"."cast_Invoice_to_type"("StandardRelations"."-ngs_Invoice_type-")', 'StandardRelations', '-ngs_Invoice_type-', 'Invoice_entity');
SELECT "-NGS-".Create_Type_Cast('"StandardRelations"."cast_Invoice_to_type"("StandardRelations"."Invoice_entity")', 'StandardRelations', 'Invoice_entity', '-ngs_Invoice_type-');
CREATE OR REPLACE FUNCTION "StandardRelations"."Invoice.FindBy"("it" "StandardRelations"."Invoice_entity", "start" INT, "end" INT) RETURNS BOOL AS 
$$
	SELECT 	 ( ((("it"))."version" >= "Invoice.FindBy"."start") AND  ((("it"))."version" <= "Invoice.FindBy"."end")) 
$$ LANGUAGE SQL IMMUTABLE SECURITY DEFINER;
CREATE OR REPLACE FUNCTION "StandardRelations"."Invoice.FindBy"("start" INT, "end" INT) RETURNS SETOF "StandardRelations"."Invoice_entity" AS 
$$SELECT * FROM "StandardRelations"."Invoice_entity" "it"  WHERE 	 ( ((("it"))."version" >= "Invoice.FindBy"."start") AND  ((("it"))."version" <= "Invoice.FindBy"."end")) 
$$ LANGUAGE SQL STABLE SECURITY DEFINER;

SELECT "-NGS-".Create_Type_Cast('"ComplexRelations"."cast_BankScrape_to_type"("ComplexRelations"."-ngs_BankScrape_type-")', 'ComplexRelations', '-ngs_BankScrape_type-', 'BankScrape_entity');
SELECT "-NGS-".Create_Type_Cast('"ComplexRelations"."cast_BankScrape_to_type"("ComplexRelations"."BankScrape_entity")', 'ComplexRelations', 'BankScrape_entity', '-ngs_BankScrape_type-');
CREATE OR REPLACE FUNCTION "ComplexRelations"."BankScrape.FindBy"("it" "ComplexRelations"."BankScrape_entity", "start" TIMESTAMPTZ, "end" TIMESTAMPTZ) RETURNS BOOL AS 
$$
	SELECT 	 ( ((("it"))."createdAt" >= "BankScrape.FindBy"."start") AND  ((("it"))."createdAt" <= "BankScrape.FindBy"."end")) 
$$ LANGUAGE SQL IMMUTABLE SECURITY DEFINER;
CREATE OR REPLACE FUNCTION "ComplexRelations"."BankScrape.FindBy"("start" TIMESTAMPTZ, "end" TIMESTAMPTZ) RETURNS SETOF "ComplexRelations"."BankScrape_entity" AS 
$$SELECT * FROM "ComplexRelations"."BankScrape_entity" "it"  WHERE 	 ( ((("it"))."createdAt" >= "BankScrape.FindBy"."start") AND  ((("it"))."createdAt" <= "BankScrape.FindBy"."end")) 
$$ LANGUAGE SQL STABLE SECURITY DEFINER;
UPDATE "ComplexObjects"."BankScrape" SET "id" = 0 WHERE "id" IS NULL;
UPDATE "ComplexObjects"."BankScrape" SET "accounts" = '{}' WHERE "accounts" IS NULL;
CREATE OR REPLACE FUNCTION "ComplexObjects"."FindMultiple"("id" INT DEFAULT 0, "ids" INT[] DEFAULT '{}', "start" TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP, "end" TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP) RETURNS record AS 
$$
DECLARE "findOne" "ComplexObjects"."BankScrape_entity";
DECLARE "findMany" "ComplexObjects"."BankScrape_entity"[];
DECLARE "findFirst" "ComplexObjects"."BankScrape_entity";
DECLARE "findLast" "ComplexObjects"."BankScrape_entity";
DECLARE "topFive" "ComplexObjects"."BankScrape_entity"[];
DECLARE "lastTen" "ComplexObjects"."BankScrape_entity"[];

DECLARE __result record;
BEGIN
	SELECT * INTO "findOne" FROM "ComplexObjects"."BankScrape_entity" "it" WHERE 	 ((("it"))."id" = "FindMultiple"."id") LIMIT 1;
	SELECT array_agg(sq."it") INTO "findMany" FROM (SELECT "it" FROM "ComplexObjects"."BankScrape_entity" "it" WHERE 	((("it"))."id" = ANY("FindMultiple"."ids"))) sq;
	SELECT * INTO "findFirst" FROM "ComplexObjects"."BankScrape_entity" "it" WHERE 	 ((("it"))."createdAt" >= "FindMultiple"."start") ORDER BY (("it"))."createdAt" LIMIT 1;
	SELECT * INTO "findLast" FROM "ComplexObjects"."BankScrape_entity" "it" WHERE 	 ((("it"))."createdAt" <= "FindMultiple"."end") ORDER BY (("it"))."createdAt" DESC LIMIT 1;
	SELECT array_agg(sq."it") INTO "topFive" FROM (SELECT "it" FROM "ComplexObjects"."BankScrape_entity" "it" WHERE 	 ( ((("it"))."createdAt" >= "FindMultiple"."start") AND  ((("it"))."createdAt" <= "FindMultiple"."end")) ORDER BY (("it"))."createdAt" LIMIT 5) sq;
	SELECT array_agg(sq."it") INTO "lastTen" FROM (SELECT "it" FROM "ComplexObjects"."BankScrape_entity" "it" WHERE 	 ( ((("it"))."createdAt" >= "FindMultiple"."start") AND  ((("it"))."createdAt" <= "FindMultiple"."end")) ORDER BY (("it"))."createdAt" DESC LIMIT 10) sq;
	
	SELECT null, CASE WHEN "findOne" IS NULL THEN NULL ELSE "findOne" END, CASE WHEN "findMany" IS NULL THEN NULL ELSE "findMany" END, CASE WHEN "findFirst" IS NULL THEN NULL ELSE "findFirst" END, CASE WHEN "findLast" IS NULL THEN NULL ELSE "findLast" END, CASE WHEN "topFive" IS NULL THEN NULL ELSE "topFive" END, CASE WHEN "lastTen" IS NULL THEN NULL ELSE "lastTen" END INTO __result;
	RETURN __result;
END;
$$ LANGUAGE PLPGSQL STABLE SECURITY DEFINER;
UPDATE "ComplexRelations"."BankScrape" SET "id" = 0 WHERE "id" IS NULL;
UPDATE "ComplexRelations"."Account" SET "balance" = 0 WHERE "balance" IS NULL;
UPDATE "ComplexRelations"."Account" SET "number" = '' WHERE "number" IS NULL;
UPDATE "ComplexRelations"."Account" SET "name" = '' WHERE "name" IS NULL;
UPDATE "ComplexRelations"."Account" SET "notes" = '' WHERE "notes" IS NULL;
UPDATE "ComplexRelations"."Transaction" SET "date" = CURRENT_DATE WHERE "date" IS NULL;
UPDATE "ComplexRelations"."Transaction" SET "description" = '' WHERE "description" IS NULL;
UPDATE "ComplexRelations"."Transaction" SET "currency" = 'EUR' WHERE "currency" IS NULL;
UPDATE "ComplexRelations"."Transaction" SET "amount" = 0 WHERE "amount" IS NULL;
CREATE OR REPLACE FUNCTION "ComplexRelations"."FindMultiple"("id" INT DEFAULT 0, "ids" INT[] DEFAULT '{}', "start" TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP, "end" TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP) RETURNS record AS 
$$
DECLARE "findOne" "ComplexRelations"."BankScrape_entity";
DECLARE "findMany" "ComplexRelations"."BankScrape_entity"[];
DECLARE "findFirst" "ComplexRelations"."BankScrape_entity";
DECLARE "findLast" "ComplexRelations"."BankScrape_entity";
DECLARE "topFive" "ComplexRelations"."BankScrape_entity"[];
DECLARE "lastTen" "ComplexRelations"."BankScrape_entity"[];

DECLARE __result record;
BEGIN
	SELECT * INTO "findOne" FROM "ComplexRelations"."BankScrape_entity" "it" WHERE 	 ((("it"))."id" = "FindMultiple"."id") LIMIT 1;
	SELECT array_agg(sq."it") INTO "findMany" FROM (SELECT "it" FROM "ComplexRelations"."BankScrape_entity" "it" WHERE 	((("it"))."id" = ANY("FindMultiple"."ids"))) sq;
	SELECT * INTO "findFirst" FROM "ComplexRelations"."BankScrape_entity" "it" WHERE 	 ((("it"))."createdAt" >= "FindMultiple"."start") ORDER BY (("it"))."createdAt" LIMIT 1;
	SELECT * INTO "findLast" FROM "ComplexRelations"."BankScrape_entity" "it" WHERE 	 ((("it"))."createdAt" <= "FindMultiple"."end") ORDER BY (("it"))."createdAt" DESC LIMIT 1;
	SELECT array_agg(sq."it") INTO "topFive" FROM (SELECT "it" FROM "ComplexRelations"."BankScrape_entity" "it" WHERE 	 ( ((("it"))."createdAt" >= "FindMultiple"."start") AND  ((("it"))."createdAt" <= "FindMultiple"."end")) ORDER BY (("it"))."createdAt" LIMIT 5) sq;
	SELECT array_agg(sq."it") INTO "lastTen" FROM (SELECT "it" FROM "ComplexRelations"."BankScrape_entity" "it" WHERE 	 ( ((("it"))."createdAt" >= "FindMultiple"."start") AND  ((("it"))."createdAt" <= "FindMultiple"."end")) ORDER BY (("it"))."createdAt" DESC LIMIT 10) sq;
	
	SELECT null, CASE WHEN "findOne" IS NULL THEN NULL ELSE "findOne" END, CASE WHEN "findMany" IS NULL THEN NULL ELSE "findMany" END, CASE WHEN "findFirst" IS NULL THEN NULL ELSE "findFirst" END, CASE WHEN "findLast" IS NULL THEN NULL ELSE "findLast" END, CASE WHEN "topFive" IS NULL THEN NULL ELSE "topFive" END, CASE WHEN "lastTen" IS NULL THEN NULL ELSE "lastTen" END INTO __result;
	RETURN __result;
END;
$$ LANGUAGE PLPGSQL STABLE SECURITY DEFINER;
UPDATE "Simple"."Post" SET "id" = '00000000-0000-0000-0000-000000000000' WHERE "id" IS NULL;
UPDATE "Simple"."Post" SET "title" = '' WHERE "title" IS NULL;
UPDATE "Simple"."Post" SET "created" = CURRENT_DATE WHERE "created" IS NULL;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_index i JOIN pg_class r ON i.indexrelid = r.oid JOIN pg_namespace n ON n.oid = r.relnamespace WHERE n.nspname = 'Simple' AND r.relname = 'ix_Post_created') THEN
		CREATE INDEX "ix_Post_created" ON "Simple"."Post" ("created");
		COMMENT ON INDEX "Simple"."ix_Post_created" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION "Simple"."FindMultiple"("id" UUID DEFAULT '00000000-0000-0000-0000-000000000000', "ids" UUID[] DEFAULT '{}', "start" DATE DEFAULT CURRENT_DATE, "end" DATE DEFAULT CURRENT_DATE) RETURNS record AS 
$$
DECLARE "findOne" "Simple"."Post_entity";
DECLARE "findMany" "Simple"."Post_entity"[];
DECLARE "findFirst" "Simple"."Post_entity";
DECLARE "findLast" "Simple"."Post_entity";
DECLARE "topFive" "Simple"."Post_entity"[];
DECLARE "lastTen" "Simple"."Post_entity"[];

DECLARE __result record;
BEGIN
	SELECT * INTO "findOne" FROM "Simple"."Post_entity" "it" WHERE 	 ((("it"))."id" = "FindMultiple"."id") LIMIT 1;
	SELECT array_agg(sq."it") INTO "findMany" FROM (SELECT "it" FROM "Simple"."Post_entity" "it" WHERE 	((("it"))."id" = ANY("FindMultiple"."ids"))) sq;
	SELECT * INTO "findFirst" FROM "Simple"."Post_entity" "it" WHERE 	 ((("it"))."created" >= "FindMultiple"."start") ORDER BY (("it"))."created" LIMIT 1;
	SELECT * INTO "findLast" FROM "Simple"."Post_entity" "it" WHERE 	 ((("it"))."created" <= "FindMultiple"."end") ORDER BY (("it"))."created" DESC LIMIT 1;
	SELECT array_agg(sq."it") INTO "topFive" FROM (SELECT "it" FROM "Simple"."Post_entity" "it" WHERE 	 ( ((("it"))."created" >= "FindMultiple"."start") AND  ((("it"))."created" <= "FindMultiple"."end")) ORDER BY (("it"))."created" LIMIT 5) sq;
	SELECT array_agg(sq."it") INTO "lastTen" FROM (SELECT "it" FROM "Simple"."Post_entity" "it" WHERE 	 ( ((("it"))."created" >= "FindMultiple"."start") AND  ((("it"))."created" <= "FindMultiple"."end")) ORDER BY (("it"))."created" DESC LIMIT 10) sq;
	
	SELECT null, CASE WHEN "findOne" IS NULL THEN NULL ELSE "findOne" END, CASE WHEN "findMany" IS NULL THEN NULL ELSE "findMany" END, CASE WHEN "findFirst" IS NULL THEN NULL ELSE "findFirst" END, CASE WHEN "findLast" IS NULL THEN NULL ELSE "findLast" END, CASE WHEN "topFive" IS NULL THEN NULL ELSE "topFive" END, CASE WHEN "lastTen" IS NULL THEN NULL ELSE "lastTen" END INTO __result;
	RETURN __result;
END;
$$ LANGUAGE PLPGSQL STABLE SECURITY DEFINER;
UPDATE "StandardObjects"."Invoice" SET "number" = '' WHERE "number" IS NULL;
UPDATE "StandardObjects"."Invoice" SET "items" = '{}' WHERE "items" IS NULL;
CREATE OR REPLACE FUNCTION "StandardObjects"."FindMultiple"("id" VARCHAR(20) DEFAULT '', "ids" VARCHAR(20)[] DEFAULT '{}', "start" BIGINT DEFAULT 0, "end" BIGINT DEFAULT 0) RETURNS record AS 
$$
DECLARE "findOne" "StandardObjects"."Invoice_entity";
DECLARE "findMany" "StandardObjects"."Invoice_entity"[];
DECLARE "findFirst" "StandardObjects"."Invoice_entity";
DECLARE "findLast" "StandardObjects"."Invoice_entity";
DECLARE "topFive" "StandardObjects"."Invoice_entity"[];
DECLARE "lastTen" "StandardObjects"."Invoice_entity"[];

DECLARE __result record;
BEGIN
	SELECT * INTO "findOne" FROM "StandardObjects"."Invoice_entity" "it" WHERE 	 ((("it"))."number" = "FindMultiple"."id") LIMIT 1;
	SELECT array_agg(sq."it") INTO "findMany" FROM (SELECT "it" FROM "StandardObjects"."Invoice_entity" "it" WHERE 	((("it"))."number" = ANY("FindMultiple"."ids"))) sq;
	SELECT * INTO "findFirst" FROM "StandardObjects"."Invoice_entity" "it" WHERE 	 ((("it"))."version" >= "FindMultiple"."start") ORDER BY (("it"))."createdAt" LIMIT 1;
	SELECT * INTO "findLast" FROM "StandardObjects"."Invoice_entity" "it" WHERE 	 ((("it"))."version" <= "FindMultiple"."end") ORDER BY (("it"))."createdAt" DESC LIMIT 1;
	SELECT array_agg(sq."it") INTO "topFive" FROM (SELECT "it" FROM "StandardObjects"."Invoice_entity" "it" WHERE 	 ( ((("it"))."version" >= "FindMultiple"."start") AND  ((("it"))."version" <= "FindMultiple"."end")) ORDER BY (("it"))."createdAt" LIMIT 5) sq;
	SELECT array_agg(sq."it") INTO "lastTen" FROM (SELECT "it" FROM "StandardObjects"."Invoice_entity" "it" WHERE 	 ( ((("it"))."version" >= "FindMultiple"."start") AND  ((("it"))."version" <= "FindMultiple"."end")) ORDER BY (("it"))."createdAt" DESC LIMIT 10) sq;
	
	SELECT null, CASE WHEN "findOne" IS NULL THEN NULL ELSE "findOne" END, CASE WHEN "findMany" IS NULL THEN NULL ELSE "findMany" END, CASE WHEN "findFirst" IS NULL THEN NULL ELSE "findFirst" END, CASE WHEN "findLast" IS NULL THEN NULL ELSE "findLast" END, CASE WHEN "topFive" IS NULL THEN NULL ELSE "topFive" END, CASE WHEN "lastTen" IS NULL THEN NULL ELSE "lastTen" END INTO __result;
	RETURN __result;
END;
$$ LANGUAGE PLPGSQL STABLE SECURITY DEFINER;
UPDATE "StandardRelations"."Invoice" SET "number" = '' WHERE "number" IS NULL;
UPDATE "StandardRelations"."Item" SET "product" = '' WHERE "product" IS NULL;
UPDATE "StandardRelations"."Item" SET "cost" = 0 WHERE "cost" IS NULL;
UPDATE "StandardRelations"."Item" SET "quantity" = 0 WHERE "quantity" IS NULL;
UPDATE "StandardRelations"."Item" SET "taxGroup" = 0 WHERE "taxGroup" IS NULL;
UPDATE "StandardRelations"."Item" SET "discount" = 0 WHERE "discount" IS NULL;
CREATE OR REPLACE FUNCTION "StandardRelations"."FindMultiple"("id" VARCHAR(20) DEFAULT '', "ids" VARCHAR(20)[] DEFAULT '{}', "start" BIGINT DEFAULT 0, "end" BIGINT DEFAULT 0) RETURNS record AS 
$$
DECLARE "findOne" "StandardRelations"."Invoice_entity";
DECLARE "findMany" "StandardRelations"."Invoice_entity"[];
DECLARE "findFirst" "StandardRelations"."Invoice_entity";
DECLARE "findLast" "StandardRelations"."Invoice_entity";
DECLARE "topFive" "StandardRelations"."Invoice_entity"[];
DECLARE "lastTen" "StandardRelations"."Invoice_entity"[];

DECLARE __result record;
BEGIN
	SELECT * INTO "findOne" FROM "StandardRelations"."Invoice_entity" "it" WHERE 	 ((("it"))."number" = "FindMultiple"."id") LIMIT 1;
	SELECT array_agg(sq."it") INTO "findMany" FROM (SELECT "it" FROM "StandardRelations"."Invoice_entity" "it" WHERE 	((("it"))."number" = ANY("FindMultiple"."ids"))) sq;
	SELECT * INTO "findFirst" FROM "StandardRelations"."Invoice_entity" "it" WHERE 	 ((("it"))."version" >= "FindMultiple"."start") ORDER BY (("it"))."createdAt" LIMIT 1;
	SELECT * INTO "findLast" FROM "StandardRelations"."Invoice_entity" "it" WHERE 	 ((("it"))."version" <= "FindMultiple"."end") ORDER BY (("it"))."createdAt" DESC LIMIT 1;
	SELECT array_agg(sq."it") INTO "topFive" FROM (SELECT "it" FROM "StandardRelations"."Invoice_entity" "it" WHERE 	 ( ((("it"))."version" >= "FindMultiple"."start") AND  ((("it"))."version" <= "FindMultiple"."end")) ORDER BY (("it"))."createdAt" LIMIT 5) sq;
	SELECT array_agg(sq."it") INTO "lastTen" FROM (SELECT "it" FROM "StandardRelations"."Invoice_entity" "it" WHERE 	 ( ((("it"))."version" >= "FindMultiple"."start") AND  ((("it"))."version" <= "FindMultiple"."end")) ORDER BY (("it"))."createdAt" DESC LIMIT 10) sq;
	
	SELECT null, CASE WHEN "findOne" IS NULL THEN NULL ELSE "findOne" END, CASE WHEN "findMany" IS NULL THEN NULL ELSE "findMany" END, CASE WHEN "findFirst" IS NULL THEN NULL ELSE "findFirst" END, CASE WHEN "findLast" IS NULL THEN NULL ELSE "findLast" END, CASE WHEN "topFive" IS NULL THEN NULL ELSE "topFive" END, CASE WHEN "lastTen" IS NULL THEN NULL ELSE "lastTen" END INTO __result;
	RETURN __result;
END;
$$ LANGUAGE PLPGSQL STABLE SECURITY DEFINER;
UPDATE "ComplexRelations"."Account" SET "BankScrapeid" = 0 WHERE "BankScrapeid" IS NULL;
UPDATE "ComplexRelations"."Account" SET "Index" = 0 WHERE "Index" IS NULL;
UPDATE "ComplexRelations"."Transaction" SET "AccountBankScrapeid" = 0 WHERE "AccountBankScrapeid" IS NULL;
UPDATE "ComplexRelations"."Transaction" SET "AccountIndex" = 0 WHERE "AccountIndex" IS NULL;
UPDATE "ComplexRelations"."Transaction" SET "Index" = 0 WHERE "Index" IS NULL;
UPDATE "StandardRelations"."Item" SET "Invoicenumber" = '' WHERE "Invoicenumber" IS NULL;
UPDATE "StandardRelations"."Item" SET "Index" = 0 WHERE "Index" IS NULL;
UPDATE "ComplexObjects"."BankScrape" SET "website" = '' WHERE "website" IS NULL;
UPDATE "ComplexObjects"."BankScrape" SET "at" = CURRENT_TIMESTAMP WHERE "at" IS NULL;
UPDATE "ComplexObjects"."BankScrape" SET "info" = '' WHERE "info" IS NULL;
UPDATE "ComplexObjects"."BankScrape" SET "ranking" = 0 WHERE "ranking" IS NULL;
UPDATE "ComplexObjects"."BankScrape" SET "tags" = '{}' WHERE "tags" IS NULL;
UPDATE "ComplexObjects"."BankScrape" SET "createdAt" = CURRENT_TIMESTAMP WHERE "createdAt" IS NULL;
UPDATE "ComplexRelations"."BankScrape" SET "website" = '' WHERE "website" IS NULL;
UPDATE "ComplexRelations"."BankScrape" SET "at" = CURRENT_TIMESTAMP WHERE "at" IS NULL;
UPDATE "ComplexRelations"."BankScrape" SET "info" = '' WHERE "info" IS NULL;
UPDATE "ComplexRelations"."BankScrape" SET "ranking" = 0 WHERE "ranking" IS NULL;
UPDATE "ComplexRelations"."BankScrape" SET "tags" = '{}' WHERE "tags" IS NULL;
UPDATE "ComplexRelations"."BankScrape" SET "createdAt" = CURRENT_TIMESTAMP WHERE "createdAt" IS NULL;
UPDATE "StandardObjects"."Invoice" SET "dueDate" = CURRENT_DATE WHERE "dueDate" IS NULL;
UPDATE "StandardObjects"."Invoice" SET "total" = 0 WHERE "total" IS NULL;
UPDATE "StandardObjects"."Invoice" SET "canceled" = false WHERE "canceled" IS NULL;
UPDATE "StandardObjects"."Invoice" SET "version" = 0 WHERE "version" IS NULL;
UPDATE "StandardObjects"."Invoice" SET "tax" = 0 WHERE "tax" IS NULL;
UPDATE "StandardObjects"."Invoice" SET "createdAt" = CURRENT_TIMESTAMP WHERE "createdAt" IS NULL;
UPDATE "StandardObjects"."Invoice" SET "modifiedAt" = CURRENT_TIMESTAMP WHERE "modifiedAt" IS NULL;
UPDATE "StandardRelations"."Invoice" SET "dueDate" = CURRENT_DATE WHERE "dueDate" IS NULL;
UPDATE "StandardRelations"."Invoice" SET "total" = 0 WHERE "total" IS NULL;
UPDATE "StandardRelations"."Invoice" SET "canceled" = false WHERE "canceled" IS NULL;
UPDATE "StandardRelations"."Invoice" SET "version" = 0 WHERE "version" IS NULL;
UPDATE "StandardRelations"."Invoice" SET "tax" = 0 WHERE "tax" IS NULL;
UPDATE "StandardRelations"."Invoice" SET "createdAt" = CURRENT_TIMESTAMP WHERE "createdAt" IS NULL;
UPDATE "StandardRelations"."Invoice" SET "modifiedAt" = CURRENT_TIMESTAMP WHERE "modifiedAt" IS NULL;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_index i JOIN pg_class r ON i.indexrelid = r.oid JOIN pg_namespace n ON n.oid = r.relnamespace WHERE n.nspname = 'ComplexObjects' AND r.relname = 'ix_BankScrape_createdAt') THEN
		CREATE INDEX "ix_BankScrape_createdAt" ON "ComplexObjects"."BankScrape" ("createdAt");
		COMMENT ON INDEX "ComplexObjects"."ix_BankScrape_createdAt" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_index i JOIN pg_class r ON i.indexrelid = r.oid JOIN pg_namespace n ON n.oid = r.relnamespace WHERE n.nspname = 'ComplexRelations' AND r.relname = 'ix_BankScrape_createdAt') THEN
		CREATE INDEX "ix_BankScrape_createdAt" ON "ComplexRelations"."BankScrape" ("createdAt");
		COMMENT ON INDEX "ComplexRelations"."ix_BankScrape_createdAt" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_index i JOIN pg_class r ON i.indexrelid = r.oid JOIN pg_namespace n ON n.oid = r.relnamespace WHERE n.nspname = 'StandardObjects' AND r.relname = 'ix_Invoice_version') THEN
		CREATE INDEX "ix_Invoice_version" ON "StandardObjects"."Invoice" ("version");
		COMMENT ON INDEX "StandardObjects"."ix_Invoice_version" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_index i JOIN pg_class r ON i.indexrelid = r.oid JOIN pg_namespace n ON n.oid = r.relnamespace WHERE n.nspname = 'StandardObjects' AND r.relname = 'ix_Invoice_createdAt') THEN
		CREATE INDEX "ix_Invoice_createdAt" ON "StandardObjects"."Invoice" ("createdAt");
		COMMENT ON INDEX "StandardObjects"."ix_Invoice_createdAt" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_index i JOIN pg_class r ON i.indexrelid = r.oid JOIN pg_namespace n ON n.oid = r.relnamespace WHERE n.nspname = 'StandardRelations' AND r.relname = 'ix_Invoice_version') THEN
		CREATE INDEX "ix_Invoice_version" ON "StandardRelations"."Invoice" ("version");
		COMMENT ON INDEX "StandardRelations"."ix_Invoice_version" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_index i JOIN pg_class r ON i.indexrelid = r.oid JOIN pg_namespace n ON n.oid = r.relnamespace WHERE n.nspname = 'StandardRelations' AND r.relname = 'ix_Invoice_createdAt') THEN
		CREATE INDEX "ix_Invoice_createdAt" ON "StandardRelations"."Invoice" ("createdAt");
		COMMENT ON INDEX "StandardRelations"."ix_Invoice_createdAt" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ 
DECLARE _pk VARCHAR;
BEGIN
	IF EXISTS(SELECT * FROM pg_index i JOIN pg_class c ON i.indrelid = c.oid JOIN pg_namespace n ON c.relnamespace = n.oid WHERE i.indisprimary AND n.nspname = 'ComplexObjects' AND c.relname = 'BankScrape') THEN
		SELECT array_to_string(array_agg(sq.attname), ', ') INTO _pk
		FROM
		(
			SELECT atr.attname
			FROM pg_index i
			JOIN pg_class c ON i.indrelid = c.oid 
			JOIN pg_attribute atr ON atr.attrelid = c.oid 
			WHERE 
				c.oid = '"ComplexObjects"."BankScrape"'::regclass
				AND atr.attnum = any(i.indkey)
				AND indisprimary
			ORDER BY (SELECT i FROM generate_subscripts(i.indkey,1) g(i) WHERE i.indkey[i] = atr.attnum LIMIT 1)
		) sq;
		IF ('id' != _pk) THEN
			RAISE EXCEPTION 'Different primary key defined for table ComplexObjects.BankScrape. Expected primary key: id. Found: %', _pk;
		END IF;
	ELSE
		ALTER TABLE "ComplexObjects"."BankScrape" ADD CONSTRAINT "pk_BankScrape" PRIMARY KEY("id");
		COMMENT ON CONSTRAINT "pk_BankScrape" ON "ComplexObjects"."BankScrape" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ 
DECLARE _pk VARCHAR;
BEGIN
	IF EXISTS(SELECT * FROM pg_index i JOIN pg_class c ON i.indrelid = c.oid JOIN pg_namespace n ON c.relnamespace = n.oid WHERE i.indisprimary AND n.nspname = 'ComplexRelations' AND c.relname = 'BankScrape') THEN
		SELECT array_to_string(array_agg(sq.attname), ', ') INTO _pk
		FROM
		(
			SELECT atr.attname
			FROM pg_index i
			JOIN pg_class c ON i.indrelid = c.oid 
			JOIN pg_attribute atr ON atr.attrelid = c.oid 
			WHERE 
				c.oid = '"ComplexRelations"."BankScrape"'::regclass
				AND atr.attnum = any(i.indkey)
				AND indisprimary
			ORDER BY (SELECT i FROM generate_subscripts(i.indkey,1) g(i) WHERE i.indkey[i] = atr.attnum LIMIT 1)
		) sq;
		IF ('id' != _pk) THEN
			RAISE EXCEPTION 'Different primary key defined for table ComplexRelations.BankScrape. Expected primary key: id. Found: %', _pk;
		END IF;
	ELSE
		ALTER TABLE "ComplexRelations"."BankScrape" ADD CONSTRAINT "pk_BankScrape" PRIMARY KEY("id");
		COMMENT ON CONSTRAINT "pk_BankScrape" ON "ComplexRelations"."BankScrape" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ 
DECLARE _pk VARCHAR;
BEGIN
	IF EXISTS(SELECT * FROM pg_index i JOIN pg_class c ON i.indrelid = c.oid JOIN pg_namespace n ON c.relnamespace = n.oid WHERE i.indisprimary AND n.nspname = 'Simple' AND c.relname = 'Post') THEN
		SELECT array_to_string(array_agg(sq.attname), ', ') INTO _pk
		FROM
		(
			SELECT atr.attname
			FROM pg_index i
			JOIN pg_class c ON i.indrelid = c.oid 
			JOIN pg_attribute atr ON atr.attrelid = c.oid 
			WHERE 
				c.oid = '"Simple"."Post"'::regclass
				AND atr.attnum = any(i.indkey)
				AND indisprimary
			ORDER BY (SELECT i FROM generate_subscripts(i.indkey,1) g(i) WHERE i.indkey[i] = atr.attnum LIMIT 1)
		) sq;
		IF ('id' != _pk) THEN
			RAISE EXCEPTION 'Different primary key defined for table Simple.Post. Expected primary key: id. Found: %', _pk;
		END IF;
	ELSE
		ALTER TABLE "Simple"."Post" ADD CONSTRAINT "pk_Post" PRIMARY KEY("id");
		COMMENT ON CONSTRAINT "pk_Post" ON "Simple"."Post" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ 
DECLARE _pk VARCHAR;
BEGIN
	IF EXISTS(SELECT * FROM pg_index i JOIN pg_class c ON i.indrelid = c.oid JOIN pg_namespace n ON c.relnamespace = n.oid WHERE i.indisprimary AND n.nspname = 'StandardObjects' AND c.relname = 'Invoice') THEN
		SELECT array_to_string(array_agg(sq.attname), ', ') INTO _pk
		FROM
		(
			SELECT atr.attname
			FROM pg_index i
			JOIN pg_class c ON i.indrelid = c.oid 
			JOIN pg_attribute atr ON atr.attrelid = c.oid 
			WHERE 
				c.oid = '"StandardObjects"."Invoice"'::regclass
				AND atr.attnum = any(i.indkey)
				AND indisprimary
			ORDER BY (SELECT i FROM generate_subscripts(i.indkey,1) g(i) WHERE i.indkey[i] = atr.attnum LIMIT 1)
		) sq;
		IF ('number' != _pk) THEN
			RAISE EXCEPTION 'Different primary key defined for table StandardObjects.Invoice. Expected primary key: number. Found: %', _pk;
		END IF;
	ELSE
		ALTER TABLE "StandardObjects"."Invoice" ADD CONSTRAINT "pk_Invoice" PRIMARY KEY("number");
		COMMENT ON CONSTRAINT "pk_Invoice" ON "StandardObjects"."Invoice" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ 
DECLARE _pk VARCHAR;
BEGIN
	IF EXISTS(SELECT * FROM pg_index i JOIN pg_class c ON i.indrelid = c.oid JOIN pg_namespace n ON c.relnamespace = n.oid WHERE i.indisprimary AND n.nspname = 'StandardRelations' AND c.relname = 'Invoice') THEN
		SELECT array_to_string(array_agg(sq.attname), ', ') INTO _pk
		FROM
		(
			SELECT atr.attname
			FROM pg_index i
			JOIN pg_class c ON i.indrelid = c.oid 
			JOIN pg_attribute atr ON atr.attrelid = c.oid 
			WHERE 
				c.oid = '"StandardRelations"."Invoice"'::regclass
				AND atr.attnum = any(i.indkey)
				AND indisprimary
			ORDER BY (SELECT i FROM generate_subscripts(i.indkey,1) g(i) WHERE i.indkey[i] = atr.attnum LIMIT 1)
		) sq;
		IF ('number' != _pk) THEN
			RAISE EXCEPTION 'Different primary key defined for table StandardRelations.Invoice. Expected primary key: number. Found: %', _pk;
		END IF;
	ELSE
		ALTER TABLE "StandardRelations"."Invoice" ADD CONSTRAINT "pk_Invoice" PRIMARY KEY("number");
		COMMENT ON CONSTRAINT "pk_Invoice" ON "StandardRelations"."Invoice" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ 
DECLARE _pk VARCHAR;
BEGIN
	IF EXISTS(SELECT * FROM pg_index i JOIN pg_class c ON i.indrelid = c.oid JOIN pg_namespace n ON c.relnamespace = n.oid WHERE i.indisprimary AND n.nspname = 'ComplexRelations' AND c.relname = 'Account') THEN
		SELECT array_to_string(array_agg(sq.attname), ', ') INTO _pk
		FROM
		(
			SELECT atr.attname
			FROM pg_index i
			JOIN pg_class c ON i.indrelid = c.oid 
			JOIN pg_attribute atr ON atr.attrelid = c.oid 
			WHERE 
				c.oid = '"ComplexRelations"."Account"'::regclass
				AND atr.attnum = any(i.indkey)
				AND indisprimary
			ORDER BY (SELECT i FROM generate_subscripts(i.indkey,1) g(i) WHERE i.indkey[i] = atr.attnum LIMIT 1)
		) sq;
		IF ('BankScrapeid, Index' != _pk) THEN
			RAISE EXCEPTION 'Different primary key defined for table ComplexRelations.Account. Expected primary key: BankScrapeid, Index. Found: %', _pk;
		END IF;
	ELSE
		ALTER TABLE "ComplexRelations"."Account" ADD CONSTRAINT "pk_Account" PRIMARY KEY("BankScrapeid","Index");
		COMMENT ON CONSTRAINT "pk_Account" ON "ComplexRelations"."Account" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ 
DECLARE _pk VARCHAR;
BEGIN
	IF EXISTS(SELECT * FROM pg_index i JOIN pg_class c ON i.indrelid = c.oid JOIN pg_namespace n ON c.relnamespace = n.oid WHERE i.indisprimary AND n.nspname = 'ComplexRelations' AND c.relname = 'Transaction') THEN
		SELECT array_to_string(array_agg(sq.attname), ', ') INTO _pk
		FROM
		(
			SELECT atr.attname
			FROM pg_index i
			JOIN pg_class c ON i.indrelid = c.oid 
			JOIN pg_attribute atr ON atr.attrelid = c.oid 
			WHERE 
				c.oid = '"ComplexRelations"."Transaction"'::regclass
				AND atr.attnum = any(i.indkey)
				AND indisprimary
			ORDER BY (SELECT i FROM generate_subscripts(i.indkey,1) g(i) WHERE i.indkey[i] = atr.attnum LIMIT 1)
		) sq;
		IF ('AccountBankScrapeid, AccountIndex, Index' != _pk) THEN
			RAISE EXCEPTION 'Different primary key defined for table ComplexRelations.Transaction. Expected primary key: AccountBankScrapeid, AccountIndex, Index. Found: %', _pk;
		END IF;
	ELSE
		ALTER TABLE "ComplexRelations"."Transaction" ADD CONSTRAINT "pk_Transaction" PRIMARY KEY("AccountBankScrapeid","AccountIndex","Index");
		COMMENT ON CONSTRAINT "pk_Transaction" ON "ComplexRelations"."Transaction" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;

DO $$ 
DECLARE _pk VARCHAR;
BEGIN
	IF EXISTS(SELECT * FROM pg_index i JOIN pg_class c ON i.indrelid = c.oid JOIN pg_namespace n ON c.relnamespace = n.oid WHERE i.indisprimary AND n.nspname = 'StandardRelations' AND c.relname = 'Item') THEN
		SELECT array_to_string(array_agg(sq.attname), ', ') INTO _pk
		FROM
		(
			SELECT atr.attname
			FROM pg_index i
			JOIN pg_class c ON i.indrelid = c.oid 
			JOIN pg_attribute atr ON atr.attrelid = c.oid 
			WHERE 
				c.oid = '"StandardRelations"."Item"'::regclass
				AND atr.attnum = any(i.indkey)
				AND indisprimary
			ORDER BY (SELECT i FROM generate_subscripts(i.indkey,1) g(i) WHERE i.indkey[i] = atr.attnum LIMIT 1)
		) sq;
		IF ('Invoicenumber, Index' != _pk) THEN
			RAISE EXCEPTION 'Different primary key defined for table StandardRelations.Item. Expected primary key: Invoicenumber, Index. Found: %', _pk;
		END IF;
	ELSE
		ALTER TABLE "StandardRelations"."Item" ADD CONSTRAINT "pk_Item" PRIMARY KEY("Invoicenumber","Index");
		COMMENT ON CONSTRAINT "pk_Item" ON "StandardRelations"."Item" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;
ALTER TABLE "ComplexObjects"."BankScrape" ALTER "id" SET NOT NULL;
ALTER TABLE "ComplexObjects"."BankScrape" ALTER "accounts" SET NOT NULL;
ALTER TABLE "ComplexRelations"."BankScrape" ALTER "id" SET NOT NULL;
ALTER TABLE "ComplexRelations"."Account" ALTER "balance" SET NOT NULL;
ALTER TABLE "ComplexRelations"."Account" ALTER "number" SET NOT NULL;
ALTER TABLE "ComplexRelations"."Account" ALTER "name" SET NOT NULL;
ALTER TABLE "ComplexRelations"."Account" ALTER "notes" SET NOT NULL;
ALTER TABLE "ComplexRelations"."Transaction" ALTER "date" SET NOT NULL;
ALTER TABLE "ComplexRelations"."Transaction" ALTER "description" SET NOT NULL;
ALTER TABLE "ComplexRelations"."Transaction" ALTER "currency" SET NOT NULL;
ALTER TABLE "ComplexRelations"."Transaction" ALTER "amount" SET NOT NULL;
ALTER TABLE "Simple"."Post" ALTER "id" SET NOT NULL;
ALTER TABLE "Simple"."Post" ALTER "title" SET NOT NULL;
ALTER TABLE "Simple"."Post" ALTER "created" SET NOT NULL;
ALTER TABLE "StandardObjects"."Invoice" ALTER "number" SET NOT NULL;
ALTER TABLE "StandardObjects"."Invoice" ALTER "items" SET NOT NULL;
ALTER TABLE "StandardRelations"."Invoice" ALTER "number" SET NOT NULL;
ALTER TABLE "StandardRelations"."Item" ALTER "product" SET NOT NULL;
ALTER TABLE "StandardRelations"."Item" ALTER "cost" SET NOT NULL;
ALTER TABLE "StandardRelations"."Item" ALTER "quantity" SET NOT NULL;
ALTER TABLE "StandardRelations"."Item" ALTER "taxGroup" SET NOT NULL;
ALTER TABLE "StandardRelations"."Item" ALTER "discount" SET NOT NULL;
ALTER TABLE "ComplexRelations"."Account" ALTER "BankScrapeid" SET NOT NULL;
ALTER TABLE "ComplexRelations"."Account" ALTER "Index" SET NOT NULL;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_constraint c JOIN pg_class r ON c.conrelid = r.oid JOIN pg_namespace n ON n.oid = r.relnamespace WHERE c.conname = 'fk_accounts' AND n.nspname = 'ComplexRelations' AND r.relname = 'Account') THEN	
		ALTER TABLE "ComplexRelations"."Account" 
			ADD CONSTRAINT "fk_accounts"
				FOREIGN KEY ("BankScrapeid") REFERENCES "ComplexRelations"."BankScrape" ("id")
				ON UPDATE CASCADE ON DELETE CASCADE;
		COMMENT ON CONSTRAINT "fk_accounts" ON "ComplexRelations"."Account" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;
ALTER TABLE "ComplexRelations"."Transaction" ALTER "AccountBankScrapeid" SET NOT NULL;
ALTER TABLE "ComplexRelations"."Transaction" ALTER "AccountIndex" SET NOT NULL;
ALTER TABLE "ComplexRelations"."Transaction" ALTER "Index" SET NOT NULL;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_constraint c JOIN pg_class r ON c.conrelid = r.oid JOIN pg_namespace n ON n.oid = r.relnamespace WHERE c.conname = 'fk_transactions' AND n.nspname = 'ComplexRelations' AND r.relname = 'Transaction') THEN	
		ALTER TABLE "ComplexRelations"."Transaction" 
			ADD CONSTRAINT "fk_transactions"
				FOREIGN KEY ("AccountBankScrapeid", "AccountIndex") REFERENCES "ComplexRelations"."Account" ("BankScrapeid", "Index")
				ON UPDATE CASCADE ON DELETE CASCADE;
		COMMENT ON CONSTRAINT "fk_transactions" ON "ComplexRelations"."Transaction" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;
ALTER TABLE "StandardRelations"."Item" ALTER "Invoicenumber" SET NOT NULL;
ALTER TABLE "StandardRelations"."Item" ALTER "Index" SET NOT NULL;

DO $$ BEGIN
	IF NOT EXISTS(SELECT * FROM pg_constraint c JOIN pg_class r ON c.conrelid = r.oid JOIN pg_namespace n ON n.oid = r.relnamespace WHERE c.conname = 'fk_items' AND n.nspname = 'StandardRelations' AND r.relname = 'Item') THEN	
		ALTER TABLE "StandardRelations"."Item" 
			ADD CONSTRAINT "fk_items"
				FOREIGN KEY ("Invoicenumber") REFERENCES "StandardRelations"."Invoice" ("number")
				ON UPDATE CASCADE ON DELETE CASCADE;
		COMMENT ON CONSTRAINT "fk_items" ON "StandardRelations"."Item" IS 'NGS generated';
	END IF;
END $$ LANGUAGE plpgsql;
ALTER TABLE "ComplexObjects"."BankScrape" ALTER "website" SET NOT NULL;
ALTER TABLE "ComplexObjects"."BankScrape" ALTER "at" SET NOT NULL;
ALTER TABLE "ComplexObjects"."BankScrape" ALTER "info" SET NOT NULL;
ALTER TABLE "ComplexObjects"."BankScrape" ALTER "ranking" SET NOT NULL;
ALTER TABLE "ComplexObjects"."BankScrape" ALTER "tags" SET NOT NULL;
ALTER TABLE "ComplexObjects"."BankScrape" ALTER "createdAt" SET NOT NULL;
ALTER TABLE "ComplexRelations"."BankScrape" ALTER "website" SET NOT NULL;
ALTER TABLE "ComplexRelations"."BankScrape" ALTER "at" SET NOT NULL;
ALTER TABLE "ComplexRelations"."BankScrape" ALTER "info" SET NOT NULL;
ALTER TABLE "ComplexRelations"."BankScrape" ALTER "ranking" SET NOT NULL;
ALTER TABLE "ComplexRelations"."BankScrape" ALTER "tags" SET NOT NULL;
ALTER TABLE "ComplexRelations"."BankScrape" ALTER "createdAt" SET NOT NULL;
ALTER TABLE "StandardObjects"."Invoice" ALTER "dueDate" SET NOT NULL;
ALTER TABLE "StandardObjects"."Invoice" ALTER "total" SET NOT NULL;
ALTER TABLE "StandardObjects"."Invoice" ALTER "canceled" SET NOT NULL;
ALTER TABLE "StandardObjects"."Invoice" ALTER "version" SET NOT NULL;
ALTER TABLE "StandardObjects"."Invoice" ALTER "tax" SET NOT NULL;
ALTER TABLE "StandardObjects"."Invoice" ALTER "createdAt" SET NOT NULL;
ALTER TABLE "StandardObjects"."Invoice" ALTER "modifiedAt" SET NOT NULL;
ALTER TABLE "StandardRelations"."Invoice" ALTER "dueDate" SET NOT NULL;
ALTER TABLE "StandardRelations"."Invoice" ALTER "total" SET NOT NULL;
ALTER TABLE "StandardRelations"."Invoice" ALTER "canceled" SET NOT NULL;
ALTER TABLE "StandardRelations"."Invoice" ALTER "version" SET NOT NULL;
ALTER TABLE "StandardRelations"."Invoice" ALTER "tax" SET NOT NULL;
ALTER TABLE "StandardRelations"."Invoice" ALTER "createdAt" SET NOT NULL;
ALTER TABLE "StandardRelations"."Invoice" ALTER "modifiedAt" SET NOT NULL;

SELECT "-NGS-".Persist_Concepts('"DSL\\ComplexModel.dsl"=>"module Complex {
	enum Currency {
		EUR;
		USD;
		Other;
	}
	mixin BankScrape {
		url website;
		timestamp at;
		map info;
		string(50)? externalId;
		int ranking;
		set<string(10)> tags;
		timestamp createdAt;
	}	
}
module ComplexObjects {
	root BankScrape(id) {
		int id;
		has mixin Complex.BankScrape;
		List<Account> accounts;
		index(createdAt);
		specification FindBy ''it => it.createdAt >= start && it.createdAt <= end'' {
			timestamp start;
			timestamp end;
		}
	}
	value Account {
		money balance;
		string(40) number;
		string(100) name;
		string(800) notes;
		List<Transaction> transactions;
	}
	value Transaction {
		date date;
		string(200) description;
		Complex.Currency currency;
		money amount;
	}

	report FindMultiple {
		int id;
		int[] ids;
		timestamp start;
		timestamp end;
		BankScrape findOne ''it => it.id == id'';
		BankScrape[] findMany ''it => ids.Contains(it.id)'';
		BankScrape findFirst ''it => it.createdAt >= start'' order by createdAt asc;
		BankScrape findLast ''it => it.createdAt <= end'' order by createdAt desc;
		BankScrape[] topFive ''it => it.createdAt >= start && it.createdAt <= end'' order by createdAt asc limit 5;
		BankScrape[] lastTen ''it => it.createdAt >= start && it.createdAt <= end'' order by createdAt desc limit 10;
	}
}

module ComplexRelations {
	root BankScrape(id) {
		int id;
		has mixin Complex.BankScrape;
		List<Account> accounts;
		index(createdAt);
		specification FindBy ''it => it.createdAt >= start && it.createdAt <= end'' {
			timestamp start;
			timestamp end;
		}
	}
	entity Account {
		money balance;
		string(40) number;
		string(100) name;
		string(800) notes;
		List<Transaction> transactions;
	}
	entity Transaction {
		date date;
		string(200) description;
		Complex.Currency currency;
		money amount;
	}

	report FindMultiple {
		int id;
		int[] ids;
		timestamp start;
		timestamp end;
		BankScrape findOne ''it => it.id == id'';
		BankScrape[] findMany ''it => ids.Contains(it.id)'';
		BankScrape findFirst ''it => it.createdAt >= start'' order by createdAt asc;
		BankScrape findLast ''it => it.createdAt <= end'' order by createdAt desc;
		BankScrape[] topFive ''it => it.createdAt >= start && it.createdAt <= end'' order by createdAt asc limit 5;
		BankScrape[] lastTen ''it => it.createdAt >= start && it.createdAt <= end'' order by createdAt desc limit 10;
	}
}

server code ''
public static partial class ChangeURI {
	public static void Change(ComplexObjects.BankScrape a, string uri) {
		a.URI = uri;
	}
	public static void Change(ComplexRelations.BankScrape a, string uri) {
		a.URI = uri;
	}
}'';", "DSL\\Global.dsl"=>"defaults {
	notifications disabled;
}", "DSL\\SimpleModel.dsl"=>"module Simple {
	root Post(id) {
		uuid id;
		string title;
		date created { index; }
		specification FindBy ''it => it.created >= start && it.created <= end'' {
			date start;
			date end;
		}
	}

	report FindMultiple {
		guid id;
		guid[] ids;
		date start;
		date end;
		Post findOne ''it => it.id == id'';
		Post[] findMany ''it => ids.Contains(it.id)'';
		Post findFirst ''it => it.created >= start'' order by created asc;
		Post findLast ''it => it.created <= end'' order by created desc;
		Post[] topFive ''it => it.created >= start && it.created <= end'' order by created asc limit 5;
		Post[] lastTen ''it => it.created >= start && it.created <= end'' order by created desc limit 10;
	}
}

server code ''
public static partial class ChangeURI {
	public static void Change(Simple.Post a, string uri) {
		a.URI = uri;
	}
}'';
", "DSL\\StandardModel.dsl"=>"module Standard {
	mixin Invoice {
		date dueDate;
		decimal total;
		datetime? paid;
		bool canceled;
		long version;
		money tax;
		string(15)? reference;
		timestamp createdAt;
		timestamp modifiedAt;
	}
}
module StandardObjects {
	root Invoice(number) {
		string(20) number;
		has mixin Standard.Invoice;
		List<Item> items;
		index(version);
		index(createdAt);
		specification FindBy ''it => it.version >= start && it.version <= end'' {
			int start;
			int end;
		}
	}
	value Item {
		string(100) product;
		decimal cost;
		int quantity;
		decimal(1) taxGroup;
		decimal(2) discount;
	}

	report FindMultiple {
		string(20) id;
		string(20)[] ids;
		long start;
		long end;
		Invoice findOne ''it => it.number == id'';
		Invoice[] findMany ''it => ids.Contains(it.number)'';
		Invoice findFirst ''it => it.version >= start'' order by createdAt asc;
		Invoice findLast ''it => it.version <= end'' order by createdAt desc;
		Invoice[] topFive ''it => it.version >= start && it.version <= end'' order by createdAt asc limit 5;
		Invoice[] lastTen ''it => it.version >= start && it.version <= end'' order by createdAt desc limit 10;
	}
}
module StandardRelations {
	root Invoice(number) {
		string(20) number;
		has mixin Standard.Invoice;
		List<Item> items;
		index(version);
		index(createdAt); //HACK: if index is missing Revenj Report is slow
		specification FindBy ''it => it.version >= start && it.version <= end'' {
			int start;
			int end;
		}
	}
	entity Item {
		string(100) product;
		decimal cost;
		int quantity;
		decimal(1) taxGroup;
		decimal(2) discount;
	}

	report FindMultiple {
		string(20) id;
		string(20)[] ids;
		long start;
		long end;
		Invoice findOne ''it => it.number == id'';
		Invoice[] findMany ''it => ids.Contains(it.number)'';
		Invoice findFirst ''it => it.version >= start'' order by createdAt asc;
		Invoice findLast ''it => it.version <= end'' order by createdAt desc;
		Invoice[] topFive ''it => it.version >= start && it.version <= end'' order by createdAt asc limit 5;
		Invoice[] lastTen ''it => it.version >= start && it.version <= end'' order by createdAt desc limit 10;
	}
}

server code ''
public static partial class ChangeURI {
	public static void Change(StandardObjects.Invoice a, string uri) {
		a.URI = uri;
	}
	public static void Change(StandardRelations.Invoice a, string uri) {
		a.URI = uri;
	}
}'';
"', '\x','1.0.5545.29383')
