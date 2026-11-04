defmodule Delivest.Repo.Migrations.BaselineOperations do
  use Ecto.Migration

  alias Delivest.Repo.Baseline

  @schema ~S"""
  -- oban_job_state; Type: TYPE
  CREATE TYPE public.oban_job_state AS ENUM (
      'available',
      'suspended',
      'scheduled',
      'executing',
      'retryable',
      'completed',
      'discarded',
      'cancelled'
  );
  -- next statement
  -- app_logs; Type: TABLE
  CREATE TABLE public.app_logs (
      id bigint NOT NULL,
      level character varying(255) NOT NULL,
      message text NOT NULL,
      source character varying(255),
      metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
      inserted_at timestamp without time zone NOT NULL
  );
  -- next statement
  -- app_logs_id_seq; Type: SEQUENCE
  CREATE SEQUENCE public.app_logs_id_seq
      START WITH 1
      INCREMENT BY 1
      NO MINVALUE
      NO MAXVALUE
      CACHE 1;
  -- next statement
  -- app_logs_id_seq; Type: SEQUENCE OWNED BY
  ALTER SEQUENCE public.app_logs_id_seq OWNED BY public.app_logs.id;
  -- next statement
  -- audit_events; Type: TABLE
  CREATE TABLE public.audit_events (
      id uuid NOT NULL,
      action character varying(255) NOT NULL,
      actor_type character varying(255) NOT NULL,
      actor_id uuid,
      actor_name character varying(255),
      subject_type character varying(255) NOT NULL,
      subject_id character varying(255),
      subject_label character varying(255),
      branch_id uuid,
      metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
      inserted_at timestamp without time zone NOT NULL
  );
  -- next statement
  -- domain_events; Type: TABLE
  CREATE TABLE public.domain_events (
      id uuid NOT NULL,
      type character varying(255) NOT NULL,
      aggregate_type character varying(255) NOT NULL,
      aggregate_id uuid NOT NULL,
      branch_id uuid,
      payload jsonb DEFAULT '{}'::jsonb NOT NULL,
      actor jsonb DEFAULT '{}'::jsonb NOT NULL,
      inserted_at timestamp without time zone NOT NULL
  );
  -- next statement
  -- oban_jobs; Type: TABLE
  CREATE TABLE public.oban_jobs (
      id bigint NOT NULL,
      state public.oban_job_state DEFAULT 'available'::public.oban_job_state NOT NULL,
      queue text DEFAULT 'default'::text NOT NULL,
      worker text NOT NULL,
      args jsonb DEFAULT '{}'::jsonb NOT NULL,
      errors jsonb[] DEFAULT ARRAY[]::jsonb[] NOT NULL,
      attempt integer DEFAULT 0 NOT NULL,
      max_attempts integer DEFAULT 20 NOT NULL,
      inserted_at timestamp without time zone DEFAULT timezone('UTC'::text, now()) NOT NULL,
      scheduled_at timestamp without time zone DEFAULT timezone('UTC'::text, now()) NOT NULL,
      attempted_at timestamp without time zone,
      completed_at timestamp without time zone,
      attempted_by text[],
      discarded_at timestamp without time zone,
      priority integer DEFAULT 0 NOT NULL,
      tags text[] DEFAULT ARRAY[]::text[],
      meta jsonb DEFAULT '{}'::jsonb,
      cancelled_at timestamp without time zone,
      CONSTRAINT attempt_range CHECK (((attempt >= 0) AND (attempt <= max_attempts))),
      CONSTRAINT positive_max_attempts CHECK ((max_attempts > 0)),
      CONSTRAINT queue_length CHECK (((char_length(queue) > 0) AND (char_length(queue) < 128))),
      CONSTRAINT worker_length CHECK (((char_length(worker) > 0) AND (char_length(worker) < 128)))
  );
  -- next statement
  -- TABLE oban_jobs; Type: COMMENT
  COMMENT ON TABLE public.oban_jobs IS '14';
  -- next statement
  -- oban_jobs_id_seq; Type: SEQUENCE
  CREATE SEQUENCE public.oban_jobs_id_seq
      START WITH 1
      INCREMENT BY 1
      NO MINVALUE
      NO MAXVALUE
      CACHE 1;
  -- next statement
  -- oban_jobs_id_seq; Type: SEQUENCE OWNED BY
  ALTER SEQUENCE public.oban_jobs_id_seq OWNED BY public.oban_jobs.id;
  -- next statement
  -- oban_peers; Type: TABLE
  CREATE UNLOGGED TABLE public.oban_peers (
      name text NOT NULL,
      node text NOT NULL,
      started_at timestamp without time zone NOT NULL,
      expires_at timestamp without time zone NOT NULL
  );
  -- next statement
  -- push_keys; Type: TABLE
  CREATE TABLE public.push_keys (
      id bigint NOT NULL,
      public_key character varying(255) NOT NULL,
      private_key character varying(255) NOT NULL,
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL
  );
  -- next statement
  -- push_keys_id_seq; Type: SEQUENCE
  CREATE SEQUENCE public.push_keys_id_seq
      START WITH 1
      INCREMENT BY 1
      NO MINVALUE
      NO MAXVALUE
      CACHE 1;
  -- next statement
  -- push_keys_id_seq; Type: SEQUENCE OWNED BY
  ALTER SEQUENCE public.push_keys_id_seq OWNED BY public.push_keys.id;
  -- next statement
  -- push_subscriptions; Type: TABLE
  CREATE TABLE public.push_subscriptions (
      id uuid NOT NULL,
      order_id uuid NOT NULL,
      endpoint text NOT NULL,
      p256dh character varying(255) NOT NULL,
      auth character varying(255) NOT NULL,
      locale character varying(255),
      notified_status character varying(255),
      inserted_at timestamp(0) without time zone NOT NULL,
      updated_at timestamp(0) without time zone NOT NULL,
      notified_courier character varying(255)
  );
  -- next statement
  -- site_snapshot_installation; Type: TABLE
  CREATE TABLE public.site_snapshot_installation (
      id integer NOT NULL,
      installation_id uuid NOT NULL
  );
  -- next statement
  -- site_snapshot_mappings; Type: TABLE
  CREATE TABLE public.site_snapshot_mappings (
      source_installation_id uuid NOT NULL,
      target_branch_id uuid NOT NULL,
      entity_type character varying(255) NOT NULL,
      source_id uuid NOT NULL,
      target_id uuid NOT NULL
  );
  -- next statement
  -- app_logs id; Type: DEFAULT
  ALTER TABLE ONLY public.app_logs ALTER COLUMN id SET DEFAULT nextval('public.app_logs_id_seq'::regclass);
  -- next statement
  -- oban_jobs id; Type: DEFAULT
  ALTER TABLE ONLY public.oban_jobs ALTER COLUMN id SET DEFAULT nextval('public.oban_jobs_id_seq'::regclass);
  -- next statement
  -- push_keys id; Type: DEFAULT
  ALTER TABLE ONLY public.push_keys ALTER COLUMN id SET DEFAULT nextval('public.push_keys_id_seq'::regclass);
  -- next statement
  -- app_logs app_logs_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.app_logs
      ADD CONSTRAINT app_logs_pkey PRIMARY KEY (id);
  -- next statement
  -- audit_events audit_events_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.audit_events
      ADD CONSTRAINT audit_events_pkey PRIMARY KEY (id);
  -- next statement
  -- domain_events domain_events_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.domain_events
      ADD CONSTRAINT domain_events_pkey PRIMARY KEY (id);
  -- next statement
  -- oban_jobs non_negative_priority; Type: CHECK CONSTRAINT
  ALTER TABLE public.oban_jobs
      ADD CONSTRAINT non_negative_priority CHECK ((priority >= 0)) NOT VALID;
  -- next statement
  -- oban_jobs oban_jobs_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.oban_jobs
      ADD CONSTRAINT oban_jobs_pkey PRIMARY KEY (id);
  -- next statement
  -- oban_peers oban_peers_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.oban_peers
      ADD CONSTRAINT oban_peers_pkey PRIMARY KEY (name);
  -- next statement
  -- push_keys push_keys_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.push_keys
      ADD CONSTRAINT push_keys_pkey PRIMARY KEY (id);
  -- next statement
  -- push_subscriptions push_subscriptions_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.push_subscriptions
      ADD CONSTRAINT push_subscriptions_pkey PRIMARY KEY (id);
  -- next statement
  -- site_snapshot_installation site_snapshot_installation_pkey; Type: CONSTRAINT
  ALTER TABLE ONLY public.site_snapshot_installation
      ADD CONSTRAINT site_snapshot_installation_pkey PRIMARY KEY (id);
  -- next statement
  -- app_logs_inserted_at_index; Type: INDEX
  CREATE INDEX app_logs_inserted_at_index ON public.app_logs USING btree (inserted_at);
  -- next statement
  -- app_logs_level_inserted_at_index; Type: INDEX
  CREATE INDEX app_logs_level_inserted_at_index ON public.app_logs USING btree (level, inserted_at);
  -- next statement
  -- audit_events_action_inserted_at_index; Type: INDEX
  CREATE INDEX audit_events_action_inserted_at_index ON public.audit_events USING btree (action, inserted_at);
  -- next statement
  -- audit_events_actor_id_inserted_at_index; Type: INDEX
  CREATE INDEX audit_events_actor_id_inserted_at_index ON public.audit_events USING btree (actor_id, inserted_at);
  -- next statement
  -- audit_events_branch_id_inserted_at_index; Type: INDEX
  CREATE INDEX audit_events_branch_id_inserted_at_index ON public.audit_events USING btree (branch_id, inserted_at);
  -- next statement
  -- audit_events_inserted_at_index; Type: INDEX
  CREATE INDEX audit_events_inserted_at_index ON public.audit_events USING btree (inserted_at);
  -- next statement
  -- audit_events_subject_type_inserted_at_index; Type: INDEX
  CREATE INDEX audit_events_subject_type_inserted_at_index ON public.audit_events USING btree (subject_type, inserted_at);
  -- next statement
  -- domain_events_aggregate_type_aggregate_id_index; Type: INDEX
  CREATE INDEX domain_events_aggregate_type_aggregate_id_index ON public.domain_events USING btree (aggregate_type, aggregate_id);
  -- next statement
  -- domain_events_branch_id_inserted_at_index; Type: INDEX
  CREATE INDEX domain_events_branch_id_inserted_at_index ON public.domain_events USING btree (branch_id, inserted_at);
  -- next statement
  -- domain_events_type_index; Type: INDEX
  CREATE INDEX domain_events_type_index ON public.domain_events USING btree (type);
  -- next statement
  -- oban_jobs_args_index; Type: INDEX
  CREATE INDEX oban_jobs_args_index ON public.oban_jobs USING gin (args);
  -- next statement
  -- oban_jobs_meta_index; Type: INDEX
  CREATE INDEX oban_jobs_meta_index ON public.oban_jobs USING gin (meta);
  -- next statement
  -- oban_jobs_state_cancelled_at_index; Type: INDEX
  CREATE INDEX oban_jobs_state_cancelled_at_index ON public.oban_jobs USING btree (state, cancelled_at);
  -- next statement
  -- oban_jobs_state_discarded_at_index; Type: INDEX
  CREATE INDEX oban_jobs_state_discarded_at_index ON public.oban_jobs USING btree (state, discarded_at);
  -- next statement
  -- oban_jobs_state_queue_priority_scheduled_at_id_index; Type: INDEX
  CREATE INDEX oban_jobs_state_queue_priority_scheduled_at_id_index ON public.oban_jobs USING btree (state, queue, priority, scheduled_at, id);
  -- next statement
  -- push_subscriptions_order_id_endpoint_index; Type: INDEX
  CREATE UNIQUE INDEX push_subscriptions_order_id_endpoint_index ON public.push_subscriptions USING btree (order_id, endpoint);
  -- next statement
  -- site_snapshot_branch_source_unique; Type: INDEX
  CREATE UNIQUE INDEX site_snapshot_branch_source_unique ON public.site_snapshot_mappings USING btree (source_installation_id, entity_type, source_id) WHERE ((entity_type)::text = 'branches'::text);
  -- next statement
  -- site_snapshot_source_unique; Type: INDEX
  CREATE UNIQUE INDEX site_snapshot_source_unique ON public.site_snapshot_mappings USING btree (source_installation_id, target_branch_id, entity_type, source_id);
  -- next statement
  -- site_snapshot_target_unique; Type: INDEX
  CREATE UNIQUE INDEX site_snapshot_target_unique ON public.site_snapshot_mappings USING btree (source_installation_id, target_branch_id, entity_type, target_id);
  -- next statement
  -- push_subscriptions push_subscriptions_order_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.push_subscriptions
      ADD CONSTRAINT push_subscriptions_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;
  -- next statement
  -- site_snapshot_mappings site_snapshot_mappings_target_branch_id_fkey; Type: FK CONSTRAINT
  ALTER TABLE ONLY public.site_snapshot_mappings
      ADD CONSTRAINT site_snapshot_mappings_target_branch_id_fkey FOREIGN KEY (target_branch_id) REFERENCES public.branches(id) ON DELETE CASCADE;
  """

  def up, do: Baseline.apply_schema(repo(), @schema)
  def down, do: Baseline.irreversible!()
end
