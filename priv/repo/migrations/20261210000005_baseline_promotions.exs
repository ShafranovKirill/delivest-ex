defmodule Delivest.Repo.Migrations.BaselinePromotions do
  use Ecto.Migration

  alias Delivest.Repo.Baseline

  @schema ~S"""
  -- promo_codes; Type: TABLE
  CREATE TABLE public.promo_codes (
      id uuid NOT NULL,
      promotion_id uuid NOT NULL,
      branch_id uuid NOT NULL,
      client_id uuid,
      code character varying(255) NOT NULL,
      usage_limit integer,
      issued_by_id uuid,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  );
  -- next statement
  -- promo_redemptions; Type: TABLE
  CREATE TABLE public.promo_redemptions (
      id uuid NOT NULL,
      promotion_id uuid NOT NULL,
      promo_code_id uuid,
      order_id uuid NOT NULL,
      client_id uuid,
      discount bigint DEFAULT 0 NOT NULL,
      inserted_at timestamp(0) without time zone NOT NULL
  );
  -- next statement
  -- promotions; Type: TABLE
  CREATE TABLE public.promotions (
      id uuid NOT NULL,
      branch_id uuid NOT NULL,
      name character varying(255) NOT NULL,
      description text,
      kind character varying(255) NOT NULL,
      rules text NOT NULL,
      enabled boolean DEFAULT true NOT NULL,
      combinable boolean DEFAULT false NOT NULL,
      priority integer DEFAULT 0 NOT NULL,
      starts_at timestamp(0) without time zone,
      ends_at timestamp(0) without time zone,
      usage_limit integer,
      per_client_limit integer,
      deleted_at timestamp(0) without time zone,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  );
  -- next statement
  -- promo_codes promo_codes_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.promo_codes
      ADD CONSTRAINT promo_codes_pkey PRIMARY KEY (id);
  -- next statement
  -- promo_redemptions promo_redemptions_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.promo_redemptions
      ADD CONSTRAINT promo_redemptions_pkey PRIMARY KEY (id);
  -- next statement
  -- promotions promotions_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.promotions
      ADD CONSTRAINT promotions_pkey PRIMARY KEY (id);
  -- next statement
  -- promo_codes_branch_id_code_index; Type: INDEX
  CREATE UNIQUE INDEX promo_codes_branch_id_code_index ON public.promo_codes USING btree (branch_id, upper((code)::text));
  -- next statement
  -- promo_codes_client_id_index; Type: INDEX
  CREATE INDEX promo_codes_client_id_index ON public.promo_codes USING btree (client_id);
  -- next statement
  -- promo_codes_promotion_id_index; Type: INDEX
  CREATE INDEX promo_codes_promotion_id_index ON public.promo_codes USING btree (promotion_id);
  -- next statement
  -- promo_redemptions_client_id_index; Type: INDEX
  CREATE INDEX promo_redemptions_client_id_index ON public.promo_redemptions USING btree (client_id);
  -- next statement
  -- promo_redemptions_order_id_promotion_id_index; Type: INDEX
  CREATE UNIQUE INDEX promo_redemptions_order_id_promotion_id_index ON public.promo_redemptions USING btree (order_id, promotion_id);
  -- next statement
  -- promo_redemptions_promo_code_id_index; Type: INDEX
  CREATE INDEX promo_redemptions_promo_code_id_index ON public.promo_redemptions USING btree (promo_code_id);
  -- next statement
  -- promo_redemptions_promotion_id_index; Type: INDEX
  CREATE INDEX promo_redemptions_promotion_id_index ON public.promo_redemptions USING btree (promotion_id);
  -- next statement
  -- promotions_branch_id_index; Type: INDEX
  CREATE INDEX promotions_branch_id_index ON public.promotions USING btree (branch_id);
  -- next statement
  -- promo_codes promo_codes_branch_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.promo_codes
      ADD CONSTRAINT promo_codes_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(id) ON DELETE CASCADE;
  -- next statement
  -- promo_codes promo_codes_client_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.promo_codes
      ADD CONSTRAINT promo_codes_client_id_fkey FOREIGN KEY (client_id) REFERENCES public.clients(id) ON DELETE CASCADE;
  -- next statement
  -- promo_codes promo_codes_promotion_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.promo_codes
      ADD CONSTRAINT promo_codes_promotion_id_fkey FOREIGN KEY (promotion_id) REFERENCES public.promotions(id) ON DELETE CASCADE;
  -- next statement
  -- promo_redemptions promo_redemptions_client_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.promo_redemptions
      ADD CONSTRAINT promo_redemptions_client_id_fkey FOREIGN KEY (client_id) REFERENCES public.clients(id) ON DELETE SET NULL;
  -- next statement
  -- promo_redemptions promo_redemptions_promo_code_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.promo_redemptions
      ADD CONSTRAINT promo_redemptions_promo_code_id_fkey FOREIGN KEY (promo_code_id) REFERENCES public.promo_codes(id) ON DELETE SET NULL;
  -- next statement
  -- promo_redemptions promo_redemptions_promotion_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.promo_redemptions
      ADD CONSTRAINT promo_redemptions_promotion_id_fkey FOREIGN KEY (promotion_id) REFERENCES public.promotions(id) ON DELETE CASCADE;
  -- next statement
  -- promotions promotions_branch_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.promotions
      ADD CONSTRAINT promotions_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(id) ON DELETE CASCADE;
  """

  def up, do: Baseline.apply_schema(repo(), @schema)
  def down, do: Baseline.irreversible!()
end
