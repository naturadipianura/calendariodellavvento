-- Apertura progressiva in novembre 2026, con il fuso Europe/Rome.
-- Richiede 003_first_six_games.sql. Preserva giochi, profili, leghe e punteggi.
begin;
alter table calendar_private.calendar_settings add column if not exists month integer not null default 12 check(month between 1 and 12);
update calendar_private.calendar_settings set year=2026,month=11,preview=false where singleton=true;

create or replace function public.calendar_day(p_day integer,p_answer integer default null,p_request uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_settings calendar_private.calendar_settings%rowtype;
  v_day calendar_private.calendar_days%rowtype;
  v_profile calendar_private.profiles%rowtype;
  v_progress calendar_private.day_progress%rowtype;
  v_correct boolean;
  v_delta integer;
  v_before integer;
begin
  select * into v_settings from calendar_private.calendar_settings where singleton=true;
  select * into v_day from calendar_private.calendar_days where day=p_day;
  if v_day.day is null then return jsonb_build_object('error','Giornata non disponibile.'); end if;
  if not v_settings.preview and (clock_timestamp() at time zone 'Europe/Rome')::date < make_date(v_settings.year,v_settings.month,p_day) then
    return jsonb_build_object('locked',true,'preview',false,'opens_on',make_date(v_settings.year,v_settings.month,p_day));
  end if;
  -- Un unico ordine dei blocchi: profilo, poi giornata. Evita conteggi doppi in richieste concorrenti.
  select p.* into v_profile from calendar_private.profiles p join calendar_private.memberships m on m.profile_id=p.id
    where m.user_id=auth.uid() for update of p;
  if v_profile.id is not null then
    select * into v_progress from calendar_private.day_progress where profile_id=v_profile.id and year=v_settings.year and day=p_day;
  end if;
  if p_answer is not null then
    if v_profile.id is null then return jsonb_build_object('error','Entra nel tuo account per salvare il risultato.','login_required',true); end if;
    if p_request is null or p_answer < 0 or p_answer >= jsonb_array_length(v_day.challenge->'options') then
      return jsonb_build_object('error','Scegli una risposta valida.');
    end if;
    if coalesce(v_progress.attempts,0)<2 and coalesce(v_progress.status,'new') in ('new','retry') and v_progress.last_request is distinct from p_request then
      v_correct := p_answer=(v_day.challenge->>'correct_index')::integer;
      v_before := v_profile.score;
      v_delta := case when v_correct then case when coalesce(v_progress.attempts,0)=0 then v_settings.correct_points else v_settings.recovery_points end else v_settings.wrong_points end;
      update calendar_private.profiles set score=greatest(0,score+v_delta),updated_at=now() where id=v_profile.id returning * into v_profile;
      v_delta := v_profile.score-v_before;
      insert into calendar_private.day_progress as dp(profile_id,year,day,attempts,status,last_answer,last_request,last_delta,day_points)
      values(v_profile.id,v_settings.year,p_day,coalesce(v_progress.attempts,0)+1,
        case when v_correct then case when coalesce(v_progress.attempts,0)=0 then 'correct' else 'recovered' end
        else case when coalesce(v_progress.attempts,0)=0 then 'retry' else 'failed' end end,
        p_answer,p_request,v_delta,coalesce(v_progress.day_points,0)+v_delta)
      on conflict(profile_id,year,day) do update set attempts=excluded.attempts,status=excluded.status,last_answer=excluded.last_answer,
        last_request=excluded.last_request,last_delta=excluded.last_delta,day_points=excluded.day_points,updated_at=now()
      returning * into v_progress;
    end if;
  end if;
  return jsonb_build_object(
    'locked',false,'preview',v_settings.preview,'year',v_settings.year,
    'rules',jsonb_build_object('correct_points',v_settings.correct_points,'wrong_points',v_settings.wrong_points,'recovery_points',v_settings.recovery_points),
    'challenge',v_day.challenge-'correct_index'-'explanation',
    'name',v_day.name,'login_required',v_profile.id is null,
    'profile',case when v_profile.id is not null then jsonb_build_object('id',v_profile.id,'name',v_profile.name,'animal',v_profile.animal,'score',v_profile.score) else null end,
    'progress',case when v_progress.attempts>0 then jsonb_build_object('attempts',v_progress.attempts,'status',v_progress.status,'last_answer',v_progress.last_answer,'last_delta',v_progress.last_delta,'day_points',v_progress.day_points) else null end,
    'explanation',case when v_progress.attempts>0 then v_day.challenge->>'explanation' else null end,
    'area',case when v_progress.attempts>0 then jsonb_build_object('name',v_day.name,'description',v_day.area_description,'image',v_day.area_image) else null end
  );
end;
$$;

create or replace function public.calendar_game(p_day integer,p_submission jsonb default null,p_request uuid default null,p_finish boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  cfg calendar_private.calendar_settings%rowtype;
  d calendar_private.calendar_days%rowtype;
  p calendar_private.profiles%rowtype;
  r calendar_private.game_results%rowtype;
  v_version text;
  score integer; best integer; before_score integer; next_total integer; delta integer;
  feedback text;
begin
  select * into cfg from calendar_private.calendar_settings where singleton=true;
  select * into d from calendar_private.calendar_days where day=p_day;
  if d.day is null then return jsonb_build_object('error','Giornata non disponibile.'); end if;
  if not cfg.preview and (clock_timestamp() at time zone 'Europe/Rome')::date<make_date(cfg.year,cfg.month,p_day) then
    return jsonb_build_object('locked',true,'preview',false,'opens_on',make_date(cfg.year,cfg.month,p_day));
  end if;
  v_version:=coalesce(d.challenge->>'version','prototype-v1');
  select pr.* into p from calendar_private.profiles pr join calendar_private.memberships m on m.profile_id=pr.id where m.user_id=auth.uid() for update of pr;
  if p.id is not null then select * into r from calendar_private.game_results g where g.profile_id=p.id and g.year=cfg.year and g.day=p_day and g.version=v_version; end if;
  if p_submission is not null or p_finish then
    if p.id is null then return jsonb_build_object('error','Entra nel tuo account per salvare i punti.'); end if;
    if p_finish then
      if r.attempts is null then return jsonb_build_object('error','Completa prima un tentativo.'); end if;
      update calendar_private.game_results g set closed=true,updated_at=now() where g.profile_id=p.id and g.year=cfg.year and g.day=p_day and g.version=v_version returning * into r;
    elsif coalesce(r.closed,false)=false and coalesce(r.attempts,0)<2 and r.last_request is distinct from p_request then
      if p_request is null then return jsonb_build_object('error','Richiesta non valida.'); end if;
      begin score:=calendar_private.score_game(d.challenge,p_submission);
      exception when others then return jsonb_build_object('error','Completa la prova con risposte valide.'); end;
      best:=greatest(coalesce(r.best_score,-2),score);
      before_score:=p.score;
      next_total:=greatest(0,p.score+case when r.attempts is null or best>r.best_score then best-coalesce(r.day_points,0) else 0 end);
      delta:=next_total-before_score;
      update calendar_private.profiles set score=next_total,updated_at=now() where id=p.id returning * into p;
      insert into calendar_private.game_results as g(profile_id,year,day,version,attempts,best_score,last_score,day_points,last_delta,last_request,closed)
        values(p.id,cfg.year,p_day,v_version,coalesce(r.attempts,0)+1,best,score,coalesce(r.day_points,0)+delta,delta,p_request,coalesce(r.attempts,0)+1>=2 or best=10)
        on conflict(profile_id,year,day,version) do update set attempts=excluded.attempts,best_score=excluded.best_score,last_score=excluded.last_score,day_points=excluded.day_points,last_delta=excluded.last_delta,last_request=excluded.last_request,closed=excluded.closed,updated_at=now()
        returning * into r;
    end if;
  end if;
  feedback:=case when r.closed then d.challenge->>'explanation' else d.challenge->>'hint' end;
  return jsonb_build_object('locked',false,'preview',cfg.preview,'year',cfg.year,'name',d.name,'login_required',p.id is null,
    'challenge',d.challenge-'scores'-'option_feedback'-'correct_index'-'solution'-'explanation'-'hint'-'sources',
    'profile',case when p.id is null then null else jsonb_build_object('id',p.id,'name',p.name,'animal',p.animal,'score',p.score) end,
    'progress',case when r.attempts is null then null else jsonb_build_object('attempts',r.attempts,'best_score',r.best_score,'last_score',r.last_score,'last_delta',r.last_delta,'day_points',r.day_points,'closed',r.closed) end,
    'explanation',feedback,'sources',case when r.closed then d.challenge->'sources' else null end,
    'area',case when r.closed then jsonb_build_object('name',d.name,'description',d.area_description,'image',d.area_image,'url',d.area_url) else null end);
end;
$$;
revoke all on function public.calendar_day(integer,integer,uuid) from public;
grant execute on function public.calendar_day(integer,integer,uuid) to anon,authenticated;
revoke all on function public.calendar_game(integer,jsonb,uuid,boolean) from public;
grant execute on function public.calendar_game(integer,jsonb,uuid,boolean) to anon,authenticated;

-- Ogni esploratore legge soltanto i propri progressi della versione corrente delle prove.
create or replace function public.calendar_progress() returns jsonb
language plpgsql security definer set search_path='' as $$
declare cfg calendar_private.calendar_settings%rowtype; v_profile uuid; v_days jsonb;
begin
  select * into cfg from calendar_private.calendar_settings where singleton=true;
  select profile_id into v_profile from calendar_private.memberships where user_id=auth.uid();
  if v_profile is null then return jsonb_build_object('login_required',true,'days','[]'::jsonb); end if;
  select coalesce(jsonb_agg(jsonb_build_object('day',g.day,'attempts',g.attempts,'closed',g.closed,'best_score',g.best_score) order by g.day),'[]'::jsonb) into v_days
  from calendar_private.game_results g join calendar_private.calendar_days d on d.day=g.day and g.version=coalesce(d.challenge->>'version','prototype-v1')
  where g.profile_id=v_profile and g.year=cfg.year;
  return jsonb_build_object('year',cfg.year,'month',cfg.month,'login_required',false,'days',v_days);
end;
$$;
revoke all on function public.calendar_progress() from public,anon;
grant execute on function public.calendar_progress() to authenticated;

commit;
