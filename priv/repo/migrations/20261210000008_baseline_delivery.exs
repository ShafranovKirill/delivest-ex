defmodule Delivest.Repo.Migrations.BaselineDelivery do
  use Ecto.Migration

  alias Delivest.Repo.Baseline

  # Cross-module foreign keys appear after both tables have been created.
  @schema ~S"""
  -- courier_settlements; Type: TABLE
  CREATE TABLE public.courier_settlements (
      id uuid NOT NULL,
      branch_id uuid NOT NULL,
      courier_id uuid NOT NULL,
      accepted_by_id uuid,
      cash_amount bigint NOT NULL,
      card_amount bigint NOT NULL,
      orders_count integer NOT NULL,
      until timestamp without time zone NOT NULL,
      inserted_at timestamp without time zone NOT NULL
  );
  -- next statement
  -- deliveries; Type: TABLE
  CREATE TABLE public.deliveries (
      id uuid NOT NULL,
      order_id uuid NOT NULL,
      branch_id uuid NOT NULL,
      provider character varying(255) NOT NULL,
      status character varying(255) NOT NULL,
      courier_id uuid,
      assigned_by_id uuid,
      close_reason character varying(255),
      external_id character varying(255),
      details jsonb DEFAULT '{}'::jsonb NOT NULL,
      assigned_at timestamp without time zone,
      picked_up_at timestamp without time zone,
      closed_at timestamp without time zone,
      inserted_at timestamp without time zone NOT NULL,
      updated_at timestamp without time zone NOT NULL
  );
  -- next statement
  -- delivery_settings; Type: TABLE
  CREATE TABLE public.delivery_settings (
      id uuid NOT NULL,
      branch_id uuid NOT NULL,
      mode character varying(255) DEFAULT 'flat'::character varying NOT NULL,
      thresholds jsonb DEFAULT '[]'::jsonb NOT NULL,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL,
      show_zones boolean DEFAULT false NOT NULL,
      outside_zones boolean DEFAULT false NOT NULL
  );
  -- next statement
  -- delivery_zones; Type: TABLE
  CREATE TABLE public.delivery_zones (
      id uuid NOT NULL,
      branch_id uuid NOT NULL,
      name character varying(255) NOT NULL,
      color character varying(255) NOT NULL,
      enabled boolean DEFAULT true NOT NULL,
      "position" integer DEFAULT 0 NOT NULL,
      polygon jsonb NOT NULL,
      geometry_version integer DEFAULT 1 NOT NULL,
      delivery_minutes integer,
      thresholds jsonb DEFAULT '[]'::jsonb NOT NULL,
      deleted_at timestamp(0) without time zone,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL,
      radius_km double precision
  );
  -- next statement
  -- yandex_delivery_journals; Type: TABLE
  CREATE TABLE public.yandex_delivery_journals (
      branch_id uuid NOT NULL,
      cursor text,
      inserted_at timestamp without time zone NOT NULL,
      updated_at timestamp without time zone NOT NULL
  );
  -- next statement
  -- courier_settlements courier_settlements_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.courier_settlements
      ADD CONSTRAINT courier_settlements_pkey PRIMARY KEY (id);
  -- next statement
  -- deliveries deliveries_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.deliveries
      ADD CONSTRAINT deliveries_pkey PRIMARY KEY (id);
  -- next statement
  -- delivery_settings delivery_settings_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.delivery_settings
      ADD CONSTRAINT delivery_settings_pkey PRIMARY KEY (id);
  -- next statement
  -- delivery_zones delivery_zones_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.delivery_zones
      ADD CONSTRAINT delivery_zones_pkey PRIMARY KEY (id);
  -- next statement
  -- yandex_delivery_journals yandex_delivery_journals_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.yandex_delivery_journals
      ADD CONSTRAINT yandex_delivery_journals_pkey PRIMARY KEY (branch_id);
  -- next statement
  -- courier_settlements_branch_id_courier_id_until_index; Type: INDEX
  CREATE INDEX courier_settlements_branch_id_courier_id_until_index ON public.courier_settlements USING btree (branch_id, courier_id, until);
  -- next statement
  -- deliveries_active_order_index; Type: INDEX
  CREATE UNIQUE INDEX deliveries_active_order_index ON public.deliveries USING btree (order_id) WHERE status IN ('searching', 'assigned', 'picked_up');
  -- next statement
  -- deliveries_branch_id_status_index; Type: INDEX
  CREATE INDEX deliveries_branch_id_status_index ON public.deliveries USING btree (branch_id, status);
  -- next statement
  -- deliveries_courier_id_branch_id_closed_at_index; Type: INDEX
  CREATE INDEX deliveries_courier_id_branch_id_closed_at_index ON public.deliveries USING btree (courier_id, branch_id, closed_at) WHERE ((status)::text = 'delivered'::text);
  -- next statement
  -- deliveries_courier_id_status_index; Type: INDEX
  CREATE INDEX deliveries_courier_id_status_index ON public.deliveries USING btree (courier_id, status);
  -- next statement
  -- deliveries_order_id_inserted_at_index; Type: INDEX
  CREATE INDEX deliveries_order_id_inserted_at_index ON public.deliveries USING btree (order_id, inserted_at);
  -- next statement
  -- deliveries_provider_external_id_index; Type: INDEX
  CREATE INDEX deliveries_provider_external_id_index ON public.deliveries USING btree (provider, external_id) WHERE (external_id IS NOT NULL);
  -- next statement
  -- delivery_settings_branch_id_index; Type: INDEX
  CREATE UNIQUE INDEX delivery_settings_branch_id_index ON public.delivery_settings USING btree (branch_id);
  -- next statement
  -- delivery_zones_branch_id_index; Type: INDEX
  CREATE INDEX delivery_zones_branch_id_index ON public.delivery_zones USING btree (branch_id);
  -- next statement
  -- courier_settlements courier_settlements_accepted_by_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.courier_settlements
      ADD CONSTRAINT courier_settlements_accepted_by_id_fkey FOREIGN KEY (accepted_by_id) REFERENCES public.staff(id) ON DELETE SET NULL;
  -- next statement
  -- courier_settlements courier_settlements_branch_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.courier_settlements
      ADD CONSTRAINT courier_settlements_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(id) ON DELETE CASCADE;
  -- next statement
  -- courier_settlements courier_settlements_courier_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.courier_settlements
      ADD CONSTRAINT courier_settlements_courier_id_fkey FOREIGN KEY (courier_id) REFERENCES public.staff(id) ON DELETE CASCADE;
  -- next statement
  -- deliveries deliveries_assigned_by_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.deliveries
      ADD CONSTRAINT deliveries_assigned_by_id_fkey FOREIGN KEY (assigned_by_id) REFERENCES public.staff(id) ON DELETE SET NULL;
  -- next statement
  -- deliveries deliveries_branch_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.deliveries
      ADD CONSTRAINT deliveries_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(id) ON DELETE CASCADE;
  -- next statement
  -- deliveries deliveries_courier_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.deliveries
      ADD CONSTRAINT deliveries_courier_id_fkey FOREIGN KEY (courier_id) REFERENCES public.staff(id) ON DELETE SET NULL;
  -- next statement
  -- deliveries deliveries_order_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.deliveries
      ADD CONSTRAINT deliveries_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;
  -- next statement
  -- delivery_settings delivery_settings_branch_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.delivery_settings
      ADD CONSTRAINT delivery_settings_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(id) ON DELETE CASCADE;
  -- next statement
  -- delivery_zones delivery_zones_branch_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.delivery_zones
      ADD CONSTRAINT delivery_zones_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(id) ON DELETE CASCADE;
  -- next statement
  -- order_payments order_payments_settlement_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.order_payments
      ADD CONSTRAINT order_payments_settlement_id_fkey FOREIGN KEY (settlement_id) REFERENCES public.courier_settlements(id) ON DELETE SET NULL;
  -- next statement
  -- yandex_delivery_journals yandex_delivery_journals_branch_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.yandex_delivery_journals
      ADD CONSTRAINT yandex_delivery_journals_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(id) ON DELETE CASCADE;
  """

  def up, do: Baseline.apply_schema(repo(), @schema)
  def down, do: Baseline.irreversible!()
end
