ALTER TABLE public.business_profiles ADD COLUMN wa_account_id text;
ALTER TABLE public.conversation_messages ADD CONSTRAINT conversation_messages_external_unique UNIQUE (tenant_id, external_id);

CREATE TABLE public.whatsapp_webhook_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES public.tenants(id) ON DELETE CASCADE,
  event text NOT NULL,
  message_id text,
  payload jsonb NOT NULL,
  received_at timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz,
  processing_error text
);
CREATE UNIQUE INDEX whatsapp_webhook_events_msg ON public.whatsapp_webhook_events (event, message_id) WHERE message_id IS NOT NULL;
GRANT SELECT ON public.whatsapp_webhook_events TO authenticated;
GRANT ALL ON public.whatsapp_webhook_events TO service_role;
ALTER TABLE public.whatsapp_webhook_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tenant select" ON public.whatsapp_webhook_events FOR SELECT TO authenticated USING (public.is_tenant_member(tenant_id));
ALTER PUBLICATION supabase_realtime ADD TABLE public.business_profiles;