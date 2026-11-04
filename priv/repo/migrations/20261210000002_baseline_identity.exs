defmodule Delivest.Repo.Migrations.BaselineIdentity do
  use Ecto.Migration

  alias Delivest.Repo.Baseline

  @schema ~S"""
  -- client_status; Type: TYPE
  CREATE TYPE public.client_status AS ENUM (
      'active',
      'blocked'
  );
  -- next statement
  -- branch_info; Type: TABLE
  CREATE TABLE public.branch_info (
      id uuid NOT NULL,
      branch_id uuid NOT NULL,
      address character varying(255),
      phone_number character varying(255),
      delivery_time integer,
      working_hours jsonb DEFAULT '{}'::jsonb,
      vk_url character varying(255),
      whatsapp_url character varying(255),
      instagram_url character varying(255),
      crm jsonb DEFAULT '{}'::jsonb NOT NULL,
      ycart_settings jsonb DEFAULT '{"enabled": false}'::jsonb,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL,
      city character varying(255),
      latitude double precision,
      longitude double precision,
      fulfillment jsonb DEFAULT '{}'::jsonb NOT NULL,
      channels jsonb,
      kitchen jsonb DEFAULT '{}'::jsonb NOT NULL,
      couriers jsonb DEFAULT '{}'::jsonb NOT NULL,
      yandex_delivery jsonb,
      board_token character varying(255),
      timezone character varying(255),
      fiscal jsonb,
      intake jsonb DEFAULT '{}'::jsonb NOT NULL,
      special_hours jsonb DEFAULT '{}'::jsonb NOT NULL,
      payments jsonb DEFAULT '{}'::jsonb NOT NULL,
      loyalty jsonb DEFAULT '{}'::jsonb NOT NULL,
      manual_rating double precision,
      CONSTRAINT manual_rating_range CHECK (((manual_rating IS NULL) OR ((manual_rating >= (1)::double precision) AND (manual_rating <= (5)::double precision))))
  );
  -- next statement
  -- branches; Type: TABLE
  CREATE TABLE public.branches (
      id uuid NOT NULL,
      name character varying(255) NOT NULL,
      slug character varying(255) NOT NULL,
      is_active boolean DEFAULT false NOT NULL,
      deleted_at timestamp(0) without time zone,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL,
      code character varying(255) NOT NULL
  );
  -- next statement
  -- client_addresses; Type: TABLE
  CREATE TABLE public.client_addresses (
      id uuid NOT NULL,
      client_id uuid NOT NULL,
      city character varying(255),
      street character varying(255) NOT NULL,
      house character varying(255),
      apartment character varying(255),
      floor character varying(255),
      entrance character varying(255),
      intercom character varying(255),
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL,
      latitude double precision,
      longitude double precision,
      comment character varying(255),
      label character varying(255),
      formatted character varying(255),
      fias_id character varying(255),
      postal_code character varying(255),
      district character varying(255),
      geo_precision smallint
  );
  -- next statement
  -- client_push_subscriptions; Type: TABLE
  CREATE TABLE public.client_push_subscriptions (
      id uuid NOT NULL,
      client_id uuid NOT NULL,
      endpoint text NOT NULL,
      p256dh character varying(255) NOT NULL,
      auth character varying(255) NOT NULL,
      locale character varying(255) DEFAULT 'ru'::character varying,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  );
  -- next statement
  -- clients; Type: TABLE
  CREATE TABLE public.clients (
      id uuid NOT NULL,
      phone character varying(255) NOT NULL,
      name character varying(255),
      status public.client_status DEFAULT 'active'::public.client_status NOT NULL,
      deleted_at timestamp(0) without time zone,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL,
      operator_note text
  );
  -- next statement
  -- phone_confirmations; Type: TABLE
  CREATE TABLE public.phone_confirmations (
      id uuid NOT NULL,
      phone character varying(255) NOT NULL,
      session_id character varying(255) NOT NULL,
      call_id character varying(255) NOT NULL,
      confirmed_at timestamp(0) without time zone,
      consumed_at timestamp(0) without time zone,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL,
      call_number character varying(255),
      mode character varying(255) DEFAULT 'inbound'::character varying NOT NULL,
      code character varying(255),
      attempts integer DEFAULT 0 NOT NULL
  );
  -- next statement
  -- roles; Type: TABLE
  CREATE TABLE public.roles (
      id uuid NOT NULL,
      name character varying(255) NOT NULL,
      permissions jsonb DEFAULT '[]'::jsonb NOT NULL,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  );
  -- next statement
  -- staff; Type: TABLE
  CREATE TABLE public.staff (
      id uuid NOT NULL,
      login character varying(255) NOT NULL,
      password_hash character varying(255) NOT NULL,
      name character varying(255),
      role_id uuid NOT NULL,
      deleted_at timestamp(0) without time zone,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL,
      phone character varying(255)
  );
  -- next statement
  -- staff_branches; Type: TABLE
  CREATE TABLE public.staff_branches (
      staff_id uuid NOT NULL,
      branch_id uuid NOT NULL,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  );
  -- next statement
  -- staff_push_subscriptions; Type: TABLE
  CREATE TABLE public.staff_push_subscriptions (
      id uuid NOT NULL,
      staff_id uuid NOT NULL,
      endpoint text NOT NULL,
      p256dh character varying(255) NOT NULL,
      auth character varying(255) NOT NULL,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  );
  -- next statement
  -- branch_info branch_info_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.branch_info
      ADD CONSTRAINT branch_info_pkey PRIMARY KEY (id);
  -- next statement
  -- branches branches_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.branches
      ADD CONSTRAINT branches_pkey PRIMARY KEY (id);
  -- next statement
  -- client_addresses client_addresses_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.client_addresses
      ADD CONSTRAINT client_addresses_pkey PRIMARY KEY (id);
  -- next statement
  -- client_push_subscriptions client_push_subscriptions_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.client_push_subscriptions
      ADD CONSTRAINT client_push_subscriptions_pkey PRIMARY KEY (id);
  -- next statement
  -- clients clients_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.clients
      ADD CONSTRAINT clients_pkey PRIMARY KEY (id);
  -- next statement
  -- phone_confirmations phone_confirmations_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.phone_confirmations
      ADD CONSTRAINT phone_confirmations_pkey PRIMARY KEY (id);
  -- next statement
  -- roles roles_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.roles
      ADD CONSTRAINT roles_pkey PRIMARY KEY (id);
  -- next statement
  -- staff_branches staff_branches_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.staff_branches
      ADD CONSTRAINT staff_branches_pkey PRIMARY KEY (staff_id, branch_id);
  -- next statement
  -- staff staff_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.staff
      ADD CONSTRAINT staff_pkey PRIMARY KEY (id);
  -- next statement
  -- staff_push_subscriptions staff_push_subscriptions_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.staff_push_subscriptions
      ADD CONSTRAINT staff_push_subscriptions_pkey PRIMARY KEY (id);
  -- next statement
  -- branch_info_board_token_index; Type: INDEX
  CREATE UNIQUE INDEX branch_info_board_token_index ON public.branch_info USING btree (board_token);
  -- next statement
  -- branch_info_branch_id_index; Type: INDEX
  CREATE INDEX branch_info_branch_id_index ON public.branch_info USING btree (branch_id);
  -- next statement
  -- branches__name__uk; Type: INDEX
  CREATE UNIQUE INDEX branches__name__uk ON public.branches USING btree (name);
  -- next statement
  -- branches__slug_uk; Type: INDEX
  CREATE UNIQUE INDEX branches__slug_uk ON public.branches USING btree (slug);
  -- next statement
  -- branches_code_uk; Type: INDEX
  CREATE UNIQUE INDEX branches_code_uk ON public.branches USING btree (code);
  -- next statement
  -- client_addresses_client_id_updated_at_index; Type: INDEX
  CREATE INDEX client_addresses_client_id_updated_at_index ON public.client_addresses USING btree (client_id, updated_at);
  -- next statement
  -- client_addresses_fias_id_index; Type: INDEX
  CREATE INDEX client_addresses_fias_id_index ON public.client_addresses USING btree (fias_id);
  -- next statement
  -- client_push_subscriptions_client_id_endpoint_index; Type: INDEX
  CREATE UNIQUE INDEX client_push_subscriptions_client_id_endpoint_index ON public.client_push_subscriptions USING btree (client_id, endpoint);
  -- next statement
  -- clients__phone__uk; Type: INDEX
  CREATE UNIQUE INDEX clients__phone__uk ON public.clients USING btree (phone) WHERE (deleted_at IS NULL);
  -- next statement
  -- clients__status__idx; Type: INDEX
  CREATE INDEX clients__status__idx ON public.clients USING btree (status);
  -- next statement
  -- phone_confirmations_call_id_index; Type: INDEX
  CREATE INDEX phone_confirmations_call_id_index ON public.phone_confirmations USING btree (call_id);
  -- next statement
  -- phone_confirmations_phone_inserted_at_index; Type: INDEX
  CREATE INDEX phone_confirmations_phone_inserted_at_index ON public.phone_confirmations USING btree (phone, inserted_at);
  -- next statement
  -- phone_confirmations_session_id_inserted_at_index; Type: INDEX
  CREATE INDEX phone_confirmations_session_id_inserted_at_index ON public.phone_confirmations USING btree (session_id, inserted_at);
  -- next statement
  -- roles__name__uk; Type: INDEX
  CREATE UNIQUE INDEX roles__name__uk ON public.roles USING btree (name);
  -- next statement
  -- staff__login__uk; Type: INDEX
  CREATE UNIQUE INDEX staff__login__uk ON public.staff USING btree (login);
  -- next statement
  -- staff_branches__staff_id_branch_id__uk; Type: INDEX
  CREATE UNIQUE INDEX staff_branches__staff_id_branch_id__uk ON public.staff_branches USING btree (staff_id, branch_id);
  -- next statement
  -- staff_branches_branch_id_index; Type: INDEX
  CREATE INDEX staff_branches_branch_id_index ON public.staff_branches USING btree (branch_id);
  -- next statement
  -- staff_push_subscriptions_endpoint_index; Type: INDEX
  CREATE UNIQUE INDEX staff_push_subscriptions_endpoint_index ON public.staff_push_subscriptions USING btree (endpoint);
  -- next statement
  -- staff_push_subscriptions_staff_id_index; Type: INDEX
  CREATE INDEX staff_push_subscriptions_staff_id_index ON public.staff_push_subscriptions USING btree (staff_id);
  -- next statement
  -- staff_role_id_index; Type: INDEX
  CREATE INDEX staff_role_id_index ON public.staff USING btree (role_id);
  -- next statement
  -- branch_info branch_info__branch_id__fk; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.branch_info
      ADD CONSTRAINT branch_info__branch_id__fk FOREIGN KEY (branch_id) REFERENCES public.branches(id) ON DELETE RESTRICT;
  -- next statement
  -- client_addresses client_addresses_client_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.client_addresses
      ADD CONSTRAINT client_addresses_client_id_fkey FOREIGN KEY (client_id) REFERENCES public.clients(id) ON DELETE CASCADE;
  -- next statement
  -- client_push_subscriptions client_push_subscriptions_client_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.client_push_subscriptions
      ADD CONSTRAINT client_push_subscriptions_client_id_fkey FOREIGN KEY (client_id) REFERENCES public.clients(id) ON DELETE CASCADE;
  -- next statement
  -- staff staff__role_id__fk; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.staff
      ADD CONSTRAINT staff__role_id__fk FOREIGN KEY (role_id) REFERENCES public.roles(id) ON DELETE RESTRICT;
  -- next statement
  -- staff_branches staff_branches__branch_id__fk; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.staff_branches
      ADD CONSTRAINT staff_branches__branch_id__fk FOREIGN KEY (branch_id) REFERENCES public.branches(id) ON DELETE CASCADE;
  -- next statement
  -- staff_branches staff_branches__staff_id__fk; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.staff_branches
      ADD CONSTRAINT staff_branches__staff_id__fk FOREIGN KEY (staff_id) REFERENCES public.staff(id) ON DELETE CASCADE;
  -- next statement
  -- staff_push_subscriptions staff_push_subscriptions_staff_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.staff_push_subscriptions
      ADD CONSTRAINT staff_push_subscriptions_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staff(id) ON DELETE CASCADE;
  """

  def up, do: Baseline.initialize(repo(), @schema)
  def down, do: Baseline.irreversible!()
end
