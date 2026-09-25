CREATE TABLE public.tenants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.tenants TO authenticated;
GRANT ALL ON public.tenants TO service_role;
ALTER TABLE public.tenants ENABLE ROW LEVEL SECURITY;
CREATE POLICY "own tenant select" ON public.tenants FOR SELECT TO authenticated USING (owner_id = auth.uid());
CREATE POLICY "own tenant insert" ON public.tenants FOR INSERT TO authenticated WITH CHECK (owner_id = auth.uid());
CREATE POLICY "own tenant update" ON public.tenants FOR UPDATE TO authenticated USING (owner_id = auth.uid());

CREATE OR REPLACE FUNCTION public.is_tenant_member(_tenant uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.tenants WHERE id = _tenant AND owner_id = auth.uid())
$$;

CREATE TABLE public.business_profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL UNIQUE REFERENCES public.tenants(id) ON DELETE CASCADE,
  business_name text NOT NULL DEFAULT '',
  industry text NOT NULL DEFAULT '',
  working_hours jsonb NOT NULL DEFAULT '{"days":[1,2,3,4,5],"start":"08:00","end":"17:00"}',
  whatsapp_status text NOT NULL DEFAULT 'disconnected',
  whatsapp_number text,
  whatsapp_last_synced_at timestamptz,
  onboarded boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.leads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  name text,
  phone text NOT NULL,
  status text NOT NULL DEFAULT 'new',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, phone)
);

CREATE TABLE public.lead_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  lead_id uuid NOT NULL REFERENCES public.leads(id) ON DELETE CASCADE,
  type text NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.conversations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  lead_id uuid NOT NULL UNIQUE REFERENCES public.leads(id) ON DELETE CASCADE,
  last_message_preview text,
  last_message_at timestamptz NOT NULL DEFAULT now(),
  unread_count int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.conversation_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  direction text NOT NULL CHECK (direction IN ('inbound','outbound')),
  body text NOT NULL,
  is_auto boolean NOT NULL DEFAULT false,
  external_id text,
  delivery_status text NOT NULL DEFAULT 'pending',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.auto_reply_configs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL UNIQUE REFERENCES public.tenants(id) ON DELETE CASCADE,
  enabled boolean NOT NULL DEFAULT true,
  greeting text NOT NULL DEFAULT 'Hi! Thanks for your message. We''ll help you right away.',
  questions jsonb NOT NULL DEFAULT '[]',
  keyword_rules jsonb NOT NULL DEFAULT '[]',
  after_hours text NOT NULL DEFAULT 'Thanks for reaching out. We''re closed right now and will reply first thing tomorrow.',
  handoff text NOT NULL DEFAULT 'Thanks! Someone from our team will contact you shortly.',
  updated_at timestamptz NOT NULL DEFAULT now()
);

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['business_profiles','leads','lead_events','conversations','conversation_messages','auto_reply_configs'] LOOP
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON public.%I TO authenticated', t);
    EXECUTE format('GRANT ALL ON public.%I TO service_role', t);
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('CREATE POLICY "tenant select" ON public.%I FOR SELECT TO authenticated USING (public.is_tenant_member(tenant_id))', t);
    EXECUTE format('CREATE POLICY "tenant insert" ON public.%I FOR INSERT TO authenticated WITH CHECK (public.is_tenant_member(tenant_id))', t);
    EXECUTE format('CREATE POLICY "tenant update" ON public.%I FOR UPDATE TO authenticated USING (public.is_tenant_member(tenant_id))', t);
    EXECUTE format('CREATE POLICY "tenant delete" ON public.%I FOR DELETE TO authenticated USING (public.is_tenant_member(tenant_id))', t);
  END LOOP;
END $$;

CREATE INDEX ON public.lead_events (tenant_id, created_at DESC);
CREATE INDEX ON public.conversations (tenant_id, last_message_at DESC);
CREATE INDEX ON public.conversation_messages (conversation_id, created_at);

ALTER PUBLICATION supabase_realtime ADD TABLE public.conversations;
ALTER PUBLICATION supabase_realtime ADD TABLE public.conversation_messages;
ALTER PUBLICATION supabase_realtime ADD TABLE public.leads;