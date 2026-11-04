defmodule Delivest.Repo.Migrations.BaselineLoyalty do
  use Ecto.Migration

  alias Delivest.Repo.Baseline

  @schema ~S"""
  -- loyalty_accounts; Type: TABLE
  CREATE TABLE public.loyalty_accounts (
      client_id uuid NOT NULL,
      balance integer DEFAULT 0 NOT NULL,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  );
  -- next statement
  -- loyalty_entries; Type: TABLE
  CREATE TABLE public.loyalty_entries (
      id uuid NOT NULL,
      client_id uuid NOT NULL,
      branch_id uuid,
      order_id uuid,
      kind character varying(255) NOT NULL,
      amount integer NOT NULL,
      remaining integer DEFAULT 0 NOT NULL,
      expires_at timestamp(0) without time zone,
      reason character varying(255),
      staff_id uuid,
      inserted_at timestamp(0) without time zone NOT NULL
  );
  -- next statement
  -- loyalty_expiry_notifications; Type: TABLE
  CREATE TABLE public.loyalty_expiry_notifications (
      id uuid NOT NULL,
      client_id uuid NOT NULL,
      expires_on date NOT NULL,
      inserted_at timestamp(0) without time zone NOT NULL
  );
  -- next statement
  -- loyalty_accounts loyalty_accounts_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.loyalty_accounts
      ADD CONSTRAINT loyalty_accounts_pkey PRIMARY KEY (client_id);
  -- next statement
  -- loyalty_entries loyalty_entries_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.loyalty_entries
      ADD CONSTRAINT loyalty_entries_pkey PRIMARY KEY (id);
  -- next statement
  -- loyalty_expiry_notifications loyalty_expiry_notifications_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.loyalty_expiry_notifications
      ADD CONSTRAINT loyalty_expiry_notifications_pkey PRIMARY KEY (id);
  -- next statement
  -- loyalty_entries_branch_id_kind_index; Type: INDEX
  CREATE INDEX loyalty_entries_branch_id_kind_index ON public.loyalty_entries USING btree (branch_id, kind);
  -- next statement
  -- loyalty_entries_client_id_inserted_at_index; Type: INDEX
  CREATE INDEX loyalty_entries_client_id_inserted_at_index ON public.loyalty_entries USING btree (client_id, inserted_at);
  -- next statement
  -- loyalty_entries_expiring_index; Type: INDEX
  CREATE INDEX loyalty_entries_expiring_index ON public.loyalty_entries USING btree (expires_at) WHERE (remaining > 0);
  -- next statement
  -- loyalty_entries_order_kind_index; Type: INDEX
  CREATE UNIQUE INDEX loyalty_entries_order_kind_index ON public.loyalty_entries USING btree (kind, order_id) WHERE order_id IS NOT NULL AND kind IN ('accrual', 'accrual_reversal', 'redeem', 'refund');
  -- next statement
  -- loyalty_expiry_notifications_client_id_expires_on_index; Type: INDEX
  CREATE UNIQUE INDEX loyalty_expiry_notifications_client_id_expires_on_index ON public.loyalty_expiry_notifications USING btree (client_id, expires_on);
  -- next statement
  -- loyalty_accounts loyalty_accounts_client_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.loyalty_accounts
      ADD CONSTRAINT loyalty_accounts_client_id_fkey FOREIGN KEY (client_id) REFERENCES public.clients(id) ON DELETE CASCADE;
  -- next statement
  -- loyalty_entries loyalty_entries_client_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.loyalty_entries
      ADD CONSTRAINT loyalty_entries_client_id_fkey FOREIGN KEY (client_id) REFERENCES public.clients(id) ON DELETE CASCADE;
  -- next statement
  -- loyalty_entries loyalty_entries_order_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.loyalty_entries
      ADD CONSTRAINT loyalty_entries_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE SET NULL;
  -- next statement
  -- loyalty_entries loyalty_entries_staff_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.loyalty_entries
      ADD CONSTRAINT loyalty_entries_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staff(id) ON DELETE SET NULL;
  -- next statement
  -- loyalty_expiry_notifications loyalty_expiry_notifications_client_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.loyalty_expiry_notifications
      ADD CONSTRAINT loyalty_expiry_notifications_client_id_fkey FOREIGN KEY (client_id) REFERENCES public.clients(id) ON DELETE CASCADE;
  """

  def up, do: Baseline.apply_schema(repo(), @schema)
  def down, do: Baseline.irreversible!()
end
