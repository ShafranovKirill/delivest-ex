defmodule Delivest.Repo.Migrations.BaselineOrders do
  use Ecto.Migration

  alias Delivest.Repo.Baseline

  # Cross-module foreign keys appear after both tables have been created.
  @schema ~S"""
  -- cart_items; Type: TABLE
  CREATE TABLE public.cart_items (
      id uuid NOT NULL,
      cart_id uuid NOT NULL,
      product_id uuid NOT NULL,
      quantity integer DEFAULT 1 NOT NULL,
      inserted_at timestamp without time zone NOT NULL,
      updated_at timestamp without time zone NOT NULL,
      modifiers jsonb DEFAULT '[]'::jsonb NOT NULL,
      modifier_key character varying(255) DEFAULT ''::character varying NOT NULL
  );
  -- next statement
  -- carts; Type: TABLE
  CREATE TABLE public.carts (
      id uuid NOT NULL,
      session_id character varying(255),
      staff_id uuid,
      client_id uuid,
      branch_id uuid,
      fulfillment_type character varying(255),
      promo_code character varying(255),
      expires_at timestamp(0) without time zone,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL,
      promo_gifts jsonb DEFAULT '{}'::jsonb NOT NULL
  );
  -- next statement
  -- fiscal_receipts; Type: TABLE
  CREATE TABLE public.fiscal_receipts (
      id uuid NOT NULL,
      order_id uuid NOT NULL,
      branch_id uuid NOT NULL,
      refund_of_id uuid,
      issued_by_id uuid,
      kind character varying(255) NOT NULL,
      stage character varying(255) NOT NULL,
      provider character varying(255) NOT NULL,
      uuid character varying(255),
      status character varying(255) DEFAULT 'pending'::character varying NOT NULL,
      amount integer NOT NULL,
      request jsonb,
      payload jsonb,
      error text,
      attempts integer DEFAULT 0 NOT NULL,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL,
      payment_ids uuid[] DEFAULT ARRAY[]::uuid[] NOT NULL,
      external_id character varying(255),
      retries integer DEFAULT 0 NOT NULL
  );
  -- next statement
  -- order_counters; Type: TABLE
  CREATE TABLE public.order_counters (
      branch_id uuid NOT NULL,
      business_date date NOT NULL,
      value integer NOT NULL
  );
  -- next statement
  -- order_item_modifiers; Type: TABLE
  CREATE TABLE public.order_item_modifiers (
      id uuid NOT NULL,
      order_item_id uuid NOT NULL,
      modifier_id uuid,
      group_name character varying(255),
      name character varying(255) NOT NULL,
      price integer DEFAULT 0 NOT NULL,
      quantity integer DEFAULT 1 NOT NULL
  );
  -- next statement
  -- order_items; Type: TABLE
  CREATE TABLE public.order_items (
      id uuid NOT NULL,
      order_id uuid NOT NULL,
      product_id uuid NOT NULL,
      title character varying(255) NOT NULL,
      price bigint NOT NULL,
      base_price bigint,
      quantity integer DEFAULT 1 NOT NULL,
      gift boolean DEFAULT false NOT NULL,
      category_id uuid,
      category_name character varying(255),
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL,
      stars_reward integer DEFAULT 0 NOT NULL,
      stars_spent integer DEFAULT 0 NOT NULL
  );
  -- next statement
  -- order_payments; Type: TABLE
  CREATE TABLE public.order_payments (
      id uuid NOT NULL,
      order_id uuid NOT NULL,
      branch_id uuid NOT NULL,
      method character varying(255) NOT NULL,
      amount integer NOT NULL,
      status character varying(255) NOT NULL,
      provider character varying(255),
      external_id character varying(255),
      collected_by_id uuid,
      cash_given integer,
      paid_at timestamp(0) without time zone,
      fiscalized_by character varying(255),
      details jsonb DEFAULT '{}'::jsonb NOT NULL,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL,
      settlement_id uuid
  );
  -- next statement
  -- order_refunds; Type: TABLE
  CREATE TABLE public.order_refunds (
      id uuid NOT NULL,
      payment_id uuid NOT NULL,
      order_id uuid NOT NULL,
      amount integer NOT NULL,
      reason character varying(255),
      status character varying(255) NOT NULL,
      provider character varying(255),
      external_id character varying(255),
      refunded_by_id uuid,
      refunded_at timestamp(0) without time zone,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  );
  -- next statement
  -- order_transitions; Type: TABLE
  CREATE TABLE public.order_transitions (
      id bigint NOT NULL,
      order_id uuid NOT NULL,
      "from" character varying(255),
      "to" character varying(255) NOT NULL,
      source character varying(255) NOT NULL,
      staff_id uuid,
      reason character varying(255),
      reverted_at timestamp without time zone,
      reverted_by_id uuid,
      revert_reason character varying(255),
      inserted_at timestamp without time zone NOT NULL
  );
  -- next statement
  -- order_transitions_id_seq; Type: SEQUENCE
  CREATE SEQUENCE public.order_transitions_id_seq
      START WITH 1
      INCREMENT BY 1
      NO MINVALUE
      NO MAXVALUE
      CACHE 1;
  -- next statement
  -- order_transitions_id_seq; Type: SEQUENCE OWNED BY
  ALTER SEQUENCE public.order_transitions_id_seq OWNED BY public.order_transitions.id;
  -- next statement
  -- orders; Type: TABLE
  CREATE TABLE public.orders (
      id uuid NOT NULL,
      number character varying(255) NOT NULL,
      branch_id uuid NOT NULL,
      cart_id uuid NOT NULL,
      staff_id uuid,
      client_id uuid,
      session_id character varying(255),
      status character varying(255) DEFAULT 'created'::character varying NOT NULL,
      fulfillment_type character varying(255) DEFAULT 'dine_in'::character varying NOT NULL,
      payment_method character varying(255) DEFAULT 'cash'::character varying NOT NULL,
      subtotal_amount bigint,
      discount_amount bigint DEFAULT 0 NOT NULL,
      total_amount bigint DEFAULT 0 NOT NULL,
      promotions jsonb DEFAULT '[]'::jsonb NOT NULL,
      address jsonb DEFAULT '{}'::jsonb,
      cook_by timestamp(0) without time zone,
      comment text,
      crm jsonb,
      deleted_at timestamp(0) without time zone,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL,
      cancel_reason character varying(255),
      cancel_note character varying(255),
      points_earned integer,
      source character varying(255) DEFAULT 'app'::character varying NOT NULL,
      channel jsonb,
      delivery_amount bigint DEFAULT 0 NOT NULL,
      cancel_acknowledged_at timestamp(0) without time zone,
      business_date date NOT NULL,
      daily_number integer NOT NULL,
      customer_name character varying(255),
      customer_phone character varying(255),
      customer_phone_ext character varying(255),
      customer_email character varying(255),
      persons integer,
      awaiting_payment boolean DEFAULT false NOT NULL,
      points_spent integer DEFAULT 0 NOT NULL
  );
  -- next statement
  -- order_transitions id; Type: DEFAULT
  ALTER TABLE ONLY public.order_transitions ALTER COLUMN id SET DEFAULT nextval('public.order_transitions_id_seq'::regclass);
  -- next statement
  -- cart_items cart_items_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.cart_items
      ADD CONSTRAINT cart_items_pkey PRIMARY KEY (id);
  -- next statement
  -- carts carts_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.carts
      ADD CONSTRAINT carts_pkey PRIMARY KEY (id);
  -- next statement
  -- fiscal_receipts fiscal_receipts_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.fiscal_receipts
      ADD CONSTRAINT fiscal_receipts_pkey PRIMARY KEY (id);
  -- next statement
  -- order_counters order_counters_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.order_counters
      ADD CONSTRAINT order_counters_pkey PRIMARY KEY (branch_id, business_date);
  -- next statement
  -- order_item_modifiers order_item_modifiers_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.order_item_modifiers
      ADD CONSTRAINT order_item_modifiers_pkey PRIMARY KEY (id);
  -- next statement
  -- order_items order_items_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.order_items
      ADD CONSTRAINT order_items_pkey PRIMARY KEY (id);
  -- next statement
  -- order_payments order_payments_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.order_payments
      ADD CONSTRAINT order_payments_pkey PRIMARY KEY (id);
  -- next statement
  -- order_refunds order_refunds_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.order_refunds
      ADD CONSTRAINT order_refunds_pkey PRIMARY KEY (id);
  -- next statement
  -- order_transitions order_transitions_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.order_transitions
      ADD CONSTRAINT order_transitions_pkey PRIMARY KEY (id);
  -- next statement
  -- orders orders_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.orders
      ADD CONSTRAINT orders_pkey PRIMARY KEY (id);
  -- next statement
  -- cart_items_cart_id_product_id_modifier_key_index; Type: INDEX
  CREATE UNIQUE INDEX cart_items_cart_id_product_id_modifier_key_index ON public.cart_items USING btree (cart_id, product_id, modifier_key);
  -- next statement
  -- carts_branch_id_index; Type: INDEX
  CREATE INDEX carts_branch_id_index ON public.carts USING btree (branch_id);
  -- next statement
  -- carts_session_id_index; Type: INDEX
  CREATE INDEX carts_session_id_index ON public.carts USING btree (session_id) WHERE (session_id IS NOT NULL);
  -- next statement
  -- carts_staff_id_index; Type: INDEX
  CREATE INDEX carts_staff_id_index ON public.carts USING btree (staff_id) WHERE (staff_id IS NOT NULL);
  -- next statement
  -- fiscal_receipts_branch_id_status_index; Type: INDEX
  CREATE INDEX fiscal_receipts_branch_id_status_index ON public.fiscal_receipts USING btree (branch_id, status);
  -- next statement
  -- fiscal_receipts_external_id_index; Type: INDEX
  CREATE INDEX fiscal_receipts_external_id_index ON public.fiscal_receipts USING btree (external_id) WHERE (external_id IS NOT NULL);
  -- next statement
  -- fiscal_receipts_one_per_order; Type: INDEX
  CREATE UNIQUE INDEX fiscal_receipts_one_per_order ON public.fiscal_receipts USING btree (order_id, kind, stage) WHERE ((status)::text <> 'fail'::text);
  -- next statement
  -- fiscal_receipts_order_id_index; Type: INDEX
  CREATE INDEX fiscal_receipts_order_id_index ON public.fiscal_receipts USING btree (order_id);
  -- next statement
  -- order_item_modifiers_order_item_id_index; Type: INDEX
  CREATE INDEX order_item_modifiers_order_item_id_index ON public.order_item_modifiers USING btree (order_item_id);
  -- next statement
  -- order_items_order_id_product_id_index; Type: INDEX
  CREATE INDEX order_items_order_id_product_id_index ON public.order_items USING btree (order_id, product_id);
  -- next statement
  -- order_items_product_id_index; Type: INDEX
  CREATE INDEX order_items_product_id_index ON public.order_items USING btree (product_id);
  -- next statement
  -- order_payments_collected_by_id_paid_at_index; Type: INDEX
  CREATE INDEX order_payments_collected_by_id_paid_at_index ON public.order_payments USING btree (collected_by_id, paid_at);
  -- next statement
  -- order_payments_order_id_index; Type: INDEX
  CREATE INDEX order_payments_order_id_index ON public.order_payments USING btree (order_id);
  -- next statement
  -- order_payments_provider_external_id_index; Type: INDEX
  CREATE UNIQUE INDEX order_payments_provider_external_id_index ON public.order_payments USING btree (provider, external_id);
  -- next statement
  -- order_payments_settlement_id_index; Type: INDEX
  CREATE INDEX order_payments_settlement_id_index ON public.order_payments USING btree (settlement_id);
  -- next statement
  -- order_refunds_order_id_index; Type: INDEX
  CREATE INDEX order_refunds_order_id_index ON public.order_refunds USING btree (order_id);
  -- next statement
  -- order_refunds_payment_id_index; Type: INDEX
  CREATE INDEX order_refunds_payment_id_index ON public.order_refunds USING btree (payment_id);
  -- next statement
  -- order_refunds_provider_external_id_index; Type: INDEX
  CREATE UNIQUE INDEX order_refunds_provider_external_id_index ON public.order_refunds USING btree (provider, external_id);
  -- next statement
  -- order_transitions_order_id_id_index; Type: INDEX
  CREATE INDEX order_transitions_order_id_id_index ON public.order_transitions USING btree (order_id, id);
  -- next statement
  -- order_transitions_to_source_index; Type: INDEX
  CREATE INDEX order_transitions_to_source_index ON public.order_transitions USING btree ("to", source) WHERE (reverted_at IS NULL);
  -- next statement
  -- orders_awaiting_payment_index; Type: INDEX
  CREATE INDEX orders_awaiting_payment_index ON public.orders USING btree (inserted_at) WHERE awaiting_payment;
  -- next statement
  -- orders_branch_id_business_date_daily_number_index; Type: INDEX
  CREATE UNIQUE INDEX orders_branch_id_business_date_daily_number_index ON public.orders USING btree (branch_id, business_date, daily_number);
  -- next statement
  -- orders_branch_id_inserted_at_index; Type: INDEX
  CREATE INDEX orders_branch_id_inserted_at_index ON public.orders USING btree (branch_id, inserted_at);
  -- next statement
  -- orders_cart_id_index; Type: INDEX
  CREATE INDEX orders_cart_id_index ON public.orders USING btree (cart_id);
  -- next statement
  -- orders_channel_external_id_index; Type: INDEX
  CREATE UNIQUE INDEX orders_channel_external_id_index ON public.orders USING btree (((channel ->> 'provider'::text)), ((channel ->> 'external_id'::text))) WHERE (channel IS NOT NULL);
  -- next statement
  -- orders_client_id_inserted_at_index; Type: INDEX
  CREATE INDEX orders_client_id_inserted_at_index ON public.orders USING btree (client_id, inserted_at) WHERE (client_id IS NOT NULL);
  -- next statement
  -- orders_crm_external_id_index; Type: INDEX
  CREATE INDEX orders_crm_external_id_index ON public.orders USING btree (branch_id, ((crm ->> 'external_id'::text))) WHERE (crm IS NOT NULL);
  -- next statement
  -- orders_number_index; Type: INDEX
  CREATE UNIQUE INDEX orders_number_index ON public.orders USING btree (number);
  -- next statement
  -- orders_open_inserted_at_index; Type: INDEX
  CREATE INDEX orders_open_inserted_at_index ON public.orders USING btree (inserted_at) WHERE status IN ('created', 'preparing', 'ready', 'delivering') AND deleted_at IS NULL;
  -- next statement
  -- orders_session_id_inserted_at_index; Type: INDEX
  CREATE INDEX orders_session_id_inserted_at_index ON public.orders USING btree (session_id, inserted_at);
  -- next statement
  -- orders_staff_id_index; Type: INDEX
  CREATE INDEX orders_staff_id_index ON public.orders USING btree (staff_id) WHERE (staff_id IS NOT NULL);
  -- next statement
  -- cart_items cart_items_cart_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.cart_items
      ADD CONSTRAINT cart_items_cart_id_fkey FOREIGN KEY (cart_id) REFERENCES public.carts(id) ON DELETE CASCADE;
  -- next statement
  -- fiscal_receipts fiscal_receipts_issued_by_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.fiscal_receipts
      ADD CONSTRAINT fiscal_receipts_issued_by_id_fkey FOREIGN KEY (issued_by_id) REFERENCES public.staff(id) ON DELETE SET NULL;
  -- next statement
  -- fiscal_receipts fiscal_receipts_order_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.fiscal_receipts
      ADD CONSTRAINT fiscal_receipts_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE RESTRICT;
  -- next statement
  -- fiscal_receipts fiscal_receipts_refund_of_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.fiscal_receipts
      ADD CONSTRAINT fiscal_receipts_refund_of_id_fkey FOREIGN KEY (refund_of_id) REFERENCES public.fiscal_receipts(id) ON DELETE SET NULL;
  -- next statement
  -- order_item_modifiers order_item_modifiers_order_item_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.order_item_modifiers
      ADD CONSTRAINT order_item_modifiers_order_item_id_fkey FOREIGN KEY (order_item_id) REFERENCES public.order_items(id) ON DELETE CASCADE;
  -- next statement
  -- order_items order_items_order_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.order_items
      ADD CONSTRAINT order_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;
  -- next statement
  -- order_payments order_payments_collected_by_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.order_payments
      ADD CONSTRAINT order_payments_collected_by_id_fkey FOREIGN KEY (collected_by_id) REFERENCES public.staff(id) ON DELETE SET NULL;
  -- next statement
  -- order_payments order_payments_order_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.order_payments
      ADD CONSTRAINT order_payments_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;
  -- next statement
  -- order_refunds order_refunds_order_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.order_refunds
      ADD CONSTRAINT order_refunds_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;
  -- next statement
  -- order_refunds order_refunds_payment_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.order_refunds
      ADD CONSTRAINT order_refunds_payment_id_fkey FOREIGN KEY (payment_id) REFERENCES public.order_payments(id) ON DELETE CASCADE;
  -- next statement
  -- order_refunds order_refunds_refunded_by_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.order_refunds
      ADD CONSTRAINT order_refunds_refunded_by_id_fkey FOREIGN KEY (refunded_by_id) REFERENCES public.staff(id) ON DELETE SET NULL;
  -- next statement
  -- order_transitions order_transitions_order_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.order_transitions
      ADD CONSTRAINT order_transitions_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;
  -- next statement
  -- order_transitions order_transitions_reverted_by_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.order_transitions
      ADD CONSTRAINT order_transitions_reverted_by_id_fkey FOREIGN KEY (reverted_by_id) REFERENCES public.staff(id) ON DELETE SET NULL;
  -- next statement
  -- order_transitions order_transitions_staff_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.order_transitions
      ADD CONSTRAINT order_transitions_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staff(id) ON DELETE SET NULL;
  -- next statement
  -- promo_redemptions promo_redemptions_order_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.promo_redemptions
      ADD CONSTRAINT promo_redemptions_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;
  """

  def up, do: Baseline.apply_schema(repo(), @schema)
  def down, do: Baseline.irreversible!()
end
