defmodule Delivest.Repo.Migrations.BaselineFranchise do
  use Ecto.Migration

  alias Delivest.Repo.Baseline

  @schema ~S"""
  -- franchise_ratings; Type: TABLE
  CREATE TABLE public.franchise_ratings (
      id uuid NOT NULL,
      provider character varying(255) NOT NULL,
      rating double precision NOT NULL,
      reviews_count integer DEFAULT 0 NOT NULL,
      fetched_at timestamp(0) without time zone NOT NULL,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  );
  -- next statement
  -- franchise_settings; Type: TABLE
  CREATE TABLE public.franchise_settings (
      id uuid NOT NULL,
      name character varying(255) NOT NULL,
      description text,
      primary_color character varying(255) NOT NULL,
      legal_form character varying(255),
      legal_name character varying(255),
      inn character varying(255),
      ogrn character varying(255),
      legal_address text,
      email character varying(255),
      phone character varying(255),
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL,
      icon_key character varying(255),
      share_image_key character varying(255),
      logo_key character varying(255),
      logo_dark_key character varying(255),
      dark_primary_color character varying(255),
      timezone character varying(255) DEFAULT 'Europe/Moscow'::character varying NOT NULL,
      yandex_org_id character varying(255),
      yandex_api_key character varying(255),
      loyalty_per_rubles integer DEFAULT 100 NOT NULL,
      loyalty_stars integer DEFAULT 5 NOT NULL,
      loyalty_expire_days integer DEFAULT 180 NOT NULL,
      client_auth_required boolean DEFAULT false NOT NULL
  );
  -- next statement
  -- legal_documents; Type: TABLE
  CREATE TABLE public.legal_documents (
      id uuid NOT NULL,
      kind character varying(255) NOT NULL,
      body text NOT NULL,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  );
  -- next statement
  -- franchise_ratings franchise_ratings_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.franchise_ratings
      ADD CONSTRAINT franchise_ratings_pkey PRIMARY KEY (id);
  -- next statement
  -- franchise_settings franchise_settings_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.franchise_settings
      ADD CONSTRAINT franchise_settings_pkey PRIMARY KEY (id);
  -- next statement
  -- legal_documents legal_documents_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.legal_documents
      ADD CONSTRAINT legal_documents_pkey PRIMARY KEY (id);
  -- next statement
  -- franchise_ratings_provider_index; Type: INDEX
  CREATE UNIQUE INDEX franchise_ratings_provider_index ON public.franchise_ratings USING btree (provider);
  -- next statement
  -- legal_documents_kind_index; Type: INDEX
  CREATE UNIQUE INDEX legal_documents_kind_index ON public.legal_documents USING btree (kind);
  -- next statement
  -- Initial franchise settings
  INSERT INTO public.franchise_settings
      (id, name, primary_color, timezone, loyalty_per_rubles, loyalty_stars, loyalty_expire_days,
       inserted_at, updated_at)
  VALUES (gen_random_uuid(), 'Delivest', '#48010c', 'Europe/Moscow', 100, 5, 180, now(), now());
  """

  def up, do: Baseline.apply_schema(repo(), @schema)
  def down, do: Baseline.irreversible!()
end
