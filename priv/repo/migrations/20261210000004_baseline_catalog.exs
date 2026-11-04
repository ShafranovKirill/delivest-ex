defmodule Delivest.Repo.Migrations.BaselineCatalog do
  use Ecto.Migration

  alias Delivest.Repo.Baseline

  @schema ~S"""
  -- drop_product_external_ids(); Type: FUNCTION
  CREATE FUNCTION public.drop_product_external_ids() RETURNS trigger
      LANGUAGE plpgsql
      AS $$
  BEGIN
    DELETE FROM external_ids WHERE entity_type = 'product' AND entity_id = OLD.id;
    RETURN OLD;
  END $$;
  -- next statement
  -- categories; Type: TABLE
  CREATE TABLE public.categories (
      id uuid NOT NULL,
      name character varying(255) NOT NULL,
      "order" double precision NOT NULL,
      is_active boolean DEFAULT false NOT NULL,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  );
  -- next statement
  -- channel_products; Type: TABLE
  CREATE TABLE public.channel_products (
      id uuid NOT NULL,
      channel character varying(255) NOT NULL,
      product_id uuid NOT NULL,
      enabled boolean DEFAULT true NOT NULL,
      price bigint,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  );
  -- next statement
  -- crm_catalog_snapshots; Type: TABLE
  CREATE TABLE public.crm_catalog_snapshots (
      id uuid NOT NULL,
      branch_id uuid NOT NULL,
      provider character varying(255) NOT NULL,
      products jsonb DEFAULT '[]'::jsonb NOT NULL,
      checked_at timestamp(0) without time zone NOT NULL
  );
  -- next statement
  -- entity_relations; Type: TABLE
  CREATE TABLE public.entity_relations (
      id uuid DEFAULT gen_random_uuid() NOT NULL,
      from_entity_type character varying(255) NOT NULL,
      from_id uuid NOT NULL,
      to_entity_type character varying(255) NOT NULL,
      to_id uuid NOT NULL,
      payload jsonb DEFAULT '{}'::jsonb,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  );
  -- next statement
  -- external_ids; Type: TABLE
  CREATE TABLE public.external_ids (
      id uuid NOT NULL,
      entity_id uuid NOT NULL,
      branch_id uuid NOT NULL,
      provider character varying(255) NOT NULL,
      external_id character varying(255) NOT NULL,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL,
      entity_type character varying(255) DEFAULT 'product'::character varying NOT NULL
  );
  -- next statement
  -- media_files; Type: TABLE
  CREATE TABLE public.media_files (
      id uuid NOT NULL,
      bucket character varying(255) NOT NULL,
      key character varying(255) NOT NULL,
      original_name character varying(255) NOT NULL,
      mime_type character varying(255) NOT NULL,
      size bigint NOT NULL,
      context character varying(255) NOT NULL,
      owner_id uuid NOT NULL,
      is_private boolean NOT NULL,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL,
      thumb_key character varying(255)
  );
  -- next statement
  -- modifier_groups; Type: TABLE
  CREATE TABLE public.modifier_groups (
      id uuid NOT NULL,
      name character varying(255) NOT NULL,
      min integer DEFAULT 0 NOT NULL,
      max integer DEFAULT 1 NOT NULL,
      "position" integer DEFAULT 0 NOT NULL,
      is_active boolean DEFAULT true NOT NULL,
      is_size boolean DEFAULT false NOT NULL,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  );
  -- next statement
  -- modifier_stops; Type: TABLE
  CREATE TABLE public.modifier_stops (
      id uuid NOT NULL,
      modifier_id uuid NOT NULL,
      branch_id uuid NOT NULL,
      until timestamp(0) without time zone,
      staff_id uuid,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  );
  -- next statement
  -- modifiers; Type: TABLE
  CREATE TABLE public.modifiers (
      id uuid NOT NULL,
      group_id uuid NOT NULL,
      name character varying(255) NOT NULL,
      price integer DEFAULT 0 NOT NULL,
      max_quantity integer DEFAULT 1 NOT NULL,
      is_default boolean DEFAULT false NOT NULL,
      weight integer,
      "position" integer DEFAULT 0 NOT NULL,
      is_active boolean DEFAULT true NOT NULL,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL,
      photo_key character varying(255)
  );
  -- next statement
  -- product_modifier_groups; Type: TABLE
  CREATE TABLE public.product_modifier_groups (
      product_id uuid NOT NULL,
      group_id uuid NOT NULL,
      "position" integer DEFAULT 0 NOT NULL
  );
  -- next statement
  -- product_stops; Type: TABLE
  CREATE TABLE public.product_stops (
      id uuid NOT NULL,
      product_id uuid NOT NULL,
      branch_id uuid NOT NULL,
      source character varying(255) NOT NULL,
      until timestamp(0) without time zone,
      staff_id uuid,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  );
  -- next statement
  -- product_tags; Type: TABLE
  CREATE TABLE public.product_tags (
      id uuid NOT NULL,
      name character varying(255) NOT NULL,
      icon character varying(255),
      icon_key character varying(255),
      "order" double precision DEFAULT 0.0 NOT NULL,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  );
  -- next statement
  -- products; Type: TABLE
  CREATE TABLE public.products (
      id uuid NOT NULL,
      name character varying(255) NOT NULL,
      slug character varying(255),
      price bigint NOT NULL,
      old_price bigint,
      description text,
      quantity integer,
      weight integer,
      is_active boolean DEFAULT true NOT NULL,
      category_id uuid,
      media_id uuid,
      deleted_at timestamp(0) without time zone,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL,
      "order" double precision,
      tags character varying(255)[] DEFAULT ARRAY[]::character varying[] NOT NULL,
      suggested boolean DEFAULT false NOT NULL,
      measure_unit character varying(255) DEFAULT 'g'::character varying NOT NULL,
      calories double precision,
      proteins double precision,
      fats double precision,
      carbohydrates double precision,
      excise character varying(255),
      vat character varying(255),
      stars_price integer,
      stars_reward integer
  );
  -- next statement
  -- stocks; Type: TABLE
  CREATE TABLE public.stocks (
      id uuid NOT NULL,
      media_id uuid NOT NULL,
      product_id uuid,
      text character varying(255),
      "order" double precision NOT NULL,
      is_active boolean DEFAULT true NOT NULL,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  );
  -- next statement
  -- categories categories_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.categories
      ADD CONSTRAINT categories_pkey PRIMARY KEY (id);
  -- next statement
  -- channel_products channel_products_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.channel_products
      ADD CONSTRAINT channel_products_pkey PRIMARY KEY (id);
  -- next statement
  -- crm_catalog_snapshots crm_catalog_snapshots_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.crm_catalog_snapshots
      ADD CONSTRAINT crm_catalog_snapshots_pkey PRIMARY KEY (id);
  -- next statement
  -- entity_relations entity_relations_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.entity_relations
      ADD CONSTRAINT entity_relations_pkey PRIMARY KEY (id);
  -- next statement
  -- media_files media_files_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.media_files
      ADD CONSTRAINT media_files_pkey PRIMARY KEY (id);
  -- next statement
  -- modifier_groups modifier_groups_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.modifier_groups
      ADD CONSTRAINT modifier_groups_pkey PRIMARY KEY (id);
  -- next statement
  -- modifier_stops modifier_stops_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.modifier_stops
      ADD CONSTRAINT modifier_stops_pkey PRIMARY KEY (id);
  -- next statement
  -- modifiers modifiers_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.modifiers
      ADD CONSTRAINT modifiers_pkey PRIMARY KEY (id);
  -- next statement
  -- external_ids product_external_ids_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.external_ids
      ADD CONSTRAINT product_external_ids_pkey PRIMARY KEY (id);
  -- next statement
  -- product_modifier_groups product_modifier_groups_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.product_modifier_groups
      ADD CONSTRAINT product_modifier_groups_pkey PRIMARY KEY (product_id, group_id);
  -- next statement
  -- product_stops product_stops_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.product_stops
      ADD CONSTRAINT product_stops_pkey PRIMARY KEY (id);
  -- next statement
  -- product_tags product_tags_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.product_tags
      ADD CONSTRAINT product_tags_pkey PRIMARY KEY (id);
  -- next statement
  -- products products_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.products
      ADD CONSTRAINT products_pkey PRIMARY KEY (id);
  -- next statement
  -- stocks stocks_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.stocks
      ADD CONSTRAINT stocks_pkey PRIMARY KEY (id);
  -- next statement
  -- channel_products_channel_product_id_index; Type: INDEX
  CREATE UNIQUE INDEX channel_products_channel_product_id_index ON public.channel_products USING btree (channel, product_id);
  -- next statement
  -- crm_catalog_snapshots_branch_id_index; Type: INDEX
  CREATE UNIQUE INDEX crm_catalog_snapshots_branch_id_index ON public.crm_catalog_snapshots USING btree (branch_id);
  -- next statement
  -- entity_relations_to_entity_type_to_id_index; Type: INDEX
  CREATE INDEX entity_relations_to_entity_type_to_id_index ON public.entity_relations USING btree (to_entity_type, to_id);
  -- next statement
  -- entity_relations_unique_index; Type: INDEX
  CREATE UNIQUE INDEX entity_relations_unique_index ON public.entity_relations USING btree (from_entity_type, from_id, to_entity_type, to_id);
  -- next statement
  -- external_ids_entity_type_branch_id_provider_external_id_index; Type: INDEX
  CREATE UNIQUE INDEX external_ids_entity_type_branch_id_provider_external_id_index ON public.external_ids USING btree (entity_type, branch_id, provider, external_id);
  -- next statement
  -- external_ids_entity_type_entity_id_provider_index; Type: INDEX
  CREATE UNIQUE INDEX external_ids_entity_type_entity_id_provider_index ON public.external_ids USING btree (entity_type, entity_id, provider);
  -- next statement
  -- media_files_bucket_key_index; Type: INDEX
  CREATE UNIQUE INDEX media_files_bucket_key_index ON public.media_files USING btree (bucket, key);
  -- next statement
  -- modifier_stops_modifier_id_branch_id_index; Type: INDEX
  CREATE UNIQUE INDEX modifier_stops_modifier_id_branch_id_index ON public.modifier_stops USING btree (modifier_id, branch_id);
  -- next statement
  -- modifiers_group_id_index; Type: INDEX
  CREATE INDEX modifiers_group_id_index ON public.modifiers USING btree (group_id);
  -- next statement
  -- product_modifier_groups_group_id_index; Type: INDEX
  CREATE INDEX product_modifier_groups_group_id_index ON public.product_modifier_groups USING btree (group_id);
  -- next statement
  -- product_stops_branch_id_index; Type: INDEX
  CREATE INDEX product_stops_branch_id_index ON public.product_stops USING btree (branch_id);
  -- next statement
  -- product_stops_product_id_source_index; Type: INDEX
  CREATE UNIQUE INDEX product_stops_product_id_source_index ON public.product_stops USING btree (product_id, source);
  -- next statement
  -- products_category_id_index; Type: INDEX
  CREATE INDEX products_category_id_index ON public.products USING btree (category_id);
  -- next statement
  -- products_slug_index; Type: INDEX
  CREATE UNIQUE INDEX products_slug_index ON public.products USING btree (slug);
  -- next statement
  -- stocks_product_id_index; Type: INDEX
  CREATE INDEX stocks_product_id_index ON public.stocks USING btree (product_id);
  -- next statement
  -- products products_external_ids_cleanup; Type: TRIGGER
  CREATE TRIGGER products_external_ids_cleanup AFTER DELETE ON public.products FOR EACH ROW EXECUTE FUNCTION public.drop_product_external_ids();
  -- next statement
  -- channel_products channel_products_product_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.channel_products
      ADD CONSTRAINT channel_products_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;
  -- next statement
  -- crm_catalog_snapshots crm_catalog_snapshots_branch_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.crm_catalog_snapshots
      ADD CONSTRAINT crm_catalog_snapshots_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(id) ON DELETE CASCADE;
  -- next statement
  -- modifier_stops modifier_stops_modifier_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.modifier_stops
      ADD CONSTRAINT modifier_stops_modifier_id_fkey FOREIGN KEY (modifier_id) REFERENCES public.modifiers(id) ON DELETE CASCADE;
  -- next statement
  -- modifiers modifiers_group_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.modifiers
      ADD CONSTRAINT modifiers_group_id_fkey FOREIGN KEY (group_id) REFERENCES public.modifier_groups(id) ON DELETE CASCADE;
  -- next statement
  -- product_modifier_groups product_modifier_groups_group_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.product_modifier_groups
      ADD CONSTRAINT product_modifier_groups_group_id_fkey FOREIGN KEY (group_id) REFERENCES public.modifier_groups(id) ON DELETE CASCADE;
  -- next statement
  -- product_modifier_groups product_modifier_groups_product_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.product_modifier_groups
      ADD CONSTRAINT product_modifier_groups_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;
  -- next statement
  -- product_stops product_stops_product_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.product_stops
      ADD CONSTRAINT product_stops_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;
  -- next statement
  -- products products_category_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.products
      ADD CONSTRAINT products_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.categories(id) ON DELETE SET NULL;
  -- next statement
  -- stocks stocks_product_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.stocks
      ADD CONSTRAINT stocks_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE SET NULL;
  -- next statement
  -- Initial product tags
  INSERT INTO public.product_tags (id, name, icon, "order", inserted_at, updated_at)
  VALUES
          (gen_random_uuid(), 'Хит', 'flame', 1, now(), now()),
          (gen_random_uuid(), 'Новинка', 'sparkles', 2, now(), now()),
          (gen_random_uuid(), 'Острое', 'pepper', 3, now(), now()),
          (gen_random_uuid(), 'Вегетарианское', 'leaf', 4, now(), now()),
          (gen_random_uuid(), 'Детям', 'mood-kid', 5, now(), now()),
          (gen_random_uuid(), 'Выгодно', 'discount', 6, now(), now());
  """

  def up, do: Baseline.apply_schema(repo(), @schema)
  def down, do: Baseline.irreversible!()
end
