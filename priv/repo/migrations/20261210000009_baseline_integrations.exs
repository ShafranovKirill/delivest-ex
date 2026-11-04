defmodule Delivest.Repo.Migrations.BaselineIntegrations do
  use Ecto.Migration

  alias Delivest.Repo.Baseline

  @schema ~S"""
  -- dadata_settings; Type: TABLE
  CREATE TABLE public.dadata_settings (
      id uuid NOT NULL,
      api_key character varying(255),
      enabled boolean DEFAULT false NOT NULL,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  );
  -- next statement
  -- integration_health; Type: TABLE
  CREATE TABLE public.integration_health (
      id uuid NOT NULL,
      provider character varying(255) NOT NULL,
      branch_id uuid,
      status character varying(255),
      message text,
      checked_at timestamp without time zone,
      warning text,
      warning_at timestamp without time zone
  );
  -- next statement
  -- integration_inbox; Type: TABLE
  CREATE TABLE public.integration_inbox (
      id uuid NOT NULL,
      provider character varying(255) NOT NULL,
      event_id character varying(255) NOT NULL,
      branch_id uuid,
      payload jsonb DEFAULT '{}'::jsonb NOT NULL,
      status character varying(255) DEFAULT 'pending'::character varying NOT NULL,
      error text,
      processed_at timestamp without time zone,
      inserted_at timestamp without time zone NOT NULL
  );
  -- next statement
  -- integration_requests; Type: TABLE
  CREATE TABLE public.integration_requests (
      id uuid NOT NULL,
      provider character varying(255) NOT NULL,
      branch_id uuid,
      order_id uuid,
      direction character varying(255) NOT NULL,
      method character varying(255) NOT NULL,
      url text NOT NULL,
      status integer,
      duration_ms integer,
      request text,
      response text,
      error text,
      inserted_at timestamp without time zone NOT NULL
  );
  -- next statement
  -- yandex_eda_busy_modes; Type: TABLE
  CREATE TABLE public.yandex_eda_busy_modes (
      branch_id uuid NOT NULL,
      extra_minutes integer NOT NULL,
      valid_till timestamp(0) without time zone NOT NULL,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  );
  -- next statement
  -- yandex_eda_settings; Type: TABLE
  CREATE TABLE public.yandex_eda_settings (
      id uuid NOT NULL,
      client_id character varying(255),
      client_secret character varying(255),
      partner_name character varying(255),
      push_client_id character varying(255),
      push_client_secret character varying(255),
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  );
  -- next statement
  -- yookassa_settings; Type: TABLE
  CREATE TABLE public.yookassa_settings (
      id uuid NOT NULL,
      shop_id character varying(255),
      secret_key character varying(255),
      webhook_token character varying(255),
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  );
  -- next statement
  -- zvonok_settings; Type: TABLE
  CREATE TABLE public.zvonok_settings (
      id uuid NOT NULL,
      public_key character varying(255),
      campaign_id character varying(255),
      webhook_token character varying(255),
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL,
      enabled boolean DEFAULT true NOT NULL,
      login_call_mode character varying(255) DEFAULT 'inbound'::character varying NOT NULL,
      dev_skip_calls boolean DEFAULT true NOT NULL
  );
  -- next statement
  -- dadata_settings dadata_settings_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.dadata_settings
      ADD CONSTRAINT dadata_settings_pkey PRIMARY KEY (id);
  -- next statement
  -- integration_health integration_health_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.integration_health
      ADD CONSTRAINT integration_health_pkey PRIMARY KEY (id);
  -- next statement
  -- integration_inbox integration_inbox_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.integration_inbox
      ADD CONSTRAINT integration_inbox_pkey PRIMARY KEY (id);
  -- next statement
  -- integration_requests integration_requests_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.integration_requests
      ADD CONSTRAINT integration_requests_pkey PRIMARY KEY (id);
  -- next statement
  -- yandex_eda_busy_modes yandex_eda_busy_modes_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.yandex_eda_busy_modes
      ADD CONSTRAINT yandex_eda_busy_modes_pkey PRIMARY KEY (branch_id);
  -- next statement
  -- yandex_eda_settings yandex_eda_settings_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.yandex_eda_settings
      ADD CONSTRAINT yandex_eda_settings_pkey PRIMARY KEY (id);
  -- next statement
  -- yookassa_settings yookassa_settings_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.yookassa_settings
      ADD CONSTRAINT yookassa_settings_pkey PRIMARY KEY (id);
  -- next statement
  -- zvonok_settings zvonok_settings_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.zvonok_settings
      ADD CONSTRAINT zvonok_settings_pkey PRIMARY KEY (id);
  -- next statement
  -- integration_health_provider_branch_id_index; Type: INDEX
  CREATE UNIQUE INDEX integration_health_provider_branch_id_index ON public.integration_health USING btree (provider, branch_id) NULLS NOT DISTINCT;
  -- next statement
  -- integration_inbox_provider_event_id_index; Type: INDEX
  CREATE UNIQUE INDEX integration_inbox_provider_event_id_index ON public.integration_inbox USING btree (provider, event_id);
  -- next statement
  -- integration_inbox_status_inserted_at_index; Type: INDEX
  CREATE INDEX integration_inbox_status_inserted_at_index ON public.integration_inbox USING btree (status, inserted_at);
  -- next statement
  -- integration_requests_inserted_at_index; Type: INDEX
  CREATE INDEX integration_requests_inserted_at_index ON public.integration_requests USING btree (inserted_at);
  -- next statement
  -- integration_requests_order_id_index; Type: INDEX
  CREATE INDEX integration_requests_order_id_index ON public.integration_requests USING btree (order_id);
  -- next statement
  -- integration_requests_provider_branch_id_inserted_at_index; Type: INDEX
  CREATE INDEX integration_requests_provider_branch_id_inserted_at_index ON public.integration_requests USING btree (provider, branch_id, inserted_at);
  """

  def up, do: Baseline.apply_schema(repo(), @schema)
  def down, do: Baseline.irreversible!()
end
