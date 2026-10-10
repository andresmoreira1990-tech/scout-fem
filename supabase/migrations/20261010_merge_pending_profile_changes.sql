-- Scout Fem: conservar todos los campos modificados en una solicitud pendiente.
-- Ejecutar en Supabase SQL Editor una vez revisado el PR; no revoca permisos ni cambia RLS.
BEGIN;

CREATE OR REPLACE FUNCTION public.submit_player_profile_change_request(
  p_profile_id text,
  p_changes jsonb
)
RETURNS public.player_profile_change_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_request public.player_profile_change_requests%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Debes iniciar sesión.' USING ERRCODE = '28000';
  END IF;

  IF p_profile_id IS NULL OR length(btrim(p_profile_id)) = 0 THEN
    RAISE EXCEPTION 'profile_id obligatorio.' USING ERRCODE = '22023';
  END IF;

  IF p_changes IS NULL
     OR jsonb_typeof(p_changes) <> 'object'
     OR p_changes = '{}'::jsonb THEN
    RAISE EXCEPTION 'Los cambios deben ser un objeto JSON no vacío.' USING ERRCODE = '22023';
  END IF;

  IF EXISTS (
    SELECT 1 FROM jsonb_object_keys(p_changes) AS k(key)
    WHERE k.key NOT IN ('currentClub', 'history')
  ) THEN
    RAISE EXCEPTION 'La solicitud contiene campos no permitidos.' USING ERRCODE = '22023';
  END IF;

  IF p_changes ? 'currentClub'
     AND jsonb_typeof(p_changes->'currentClub') NOT IN ('string', 'null') THEN
    RAISE EXCEPTION 'Formato no válido para currentClub.' USING ERRCODE = '22023';
  END IF;

  IF p_changes ? 'history'
     AND jsonb_typeof(p_changes->'history') NOT IN ('array', 'null') THEN
    RAISE EXCEPTION 'Formato no válido para history.' USING ERRCODE = '22023';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.player_profiles pp
    WHERE pp.profile_id = p_profile_id AND pp.user_id = v_uid
  ) THEN
    RAISE EXCEPTION 'No tienes permiso para solicitar cambios en este perfil.' USING ERRCODE = '42501';
  END IF;

  -- Serializa envíos simultáneos del mismo perfil por el mismo usuario.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_profile_id || ':' || v_uid::text, 0)
  );

  SELECT * INTO v_request
  FROM public.player_profile_change_requests r
  WHERE r.profile_id = p_profile_id
    AND r.user_id = v_uid
    AND r.status = 'pending'
  ORDER BY r.created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF FOUND THEN
    -- Combina las claves nuevas con las ya pendientes: no pierde el cambio de equipo
    -- si el siguiente envío solo modifica el historial, ni viceversa.
    UPDATE public.player_profile_change_requests r
    SET changes = COALESCE(r.changes, '{}'::jsonb) || p_changes
    WHERE r.id = v_request.id
    RETURNING r.* INTO v_request;
  ELSE
    INSERT INTO public.player_profile_change_requests (profile_id, user_id, changes, status)
    VALUES (p_profile_id, v_uid, p_changes, 'pending')
    RETURNING * INTO v_request;
  END IF;

  RETURN v_request;
END;
$function$;

-- Mantener los permisos ya verificados; no cambiar grants ni ejecutar fase 2 aquí.
COMMIT;
