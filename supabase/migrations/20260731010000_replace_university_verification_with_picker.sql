-- University membership is now a user-selected value from the app's fixed list.
-- Anonymous authentication remains in place to associate the selection with a profile.
create or replace function public.get_university_status()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('school_key', p.university_school_key)
  from public.profiles p
  where p.id = auth.uid();
$$;

create or replace function public.set_university(p_school_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_allowed constant text[] := array[
    'non-school',
    'air-force', 'alabama', 'alaska', 'arizona-state', 'arkansas', 'auburn', 'baylor', 'boise-state',
    'boston-college', 'boston-university', 'brown', 'byu', 'caltech', 'carnegie-mellon', 'case-western', 'clemson',
    'columbia', 'connecticut', 'cornell', 'dartmouth', 'delaware', 'duke', 'emory', 'florida',
    'florida-state', 'george-washington', 'georgetown', 'georgia', 'georgia-tech', 'harvard', 'hawaii', 'houston',
    'howard', 'idaho', 'indiana', 'iowa', 'iowa-state', 'johns-hopkins', 'kansas', 'kansas-state',
    'kentucky', 'lsu', 'maine', 'maryland', 'miami', 'michigan-state', 'minnesota', 'mississippi',
    'mississippi-state', 'missouri', 'mit', 'montana', 'montana-state', 'naval-academy', 'nebraska', 'nevada-reno',
    'new-hampshire', 'new-mexico', 'new-mexico-state', 'notre-dame', 'nyu', 'north-carolina-state', 'north-dakota', 'north-dakota-state',
    'northeastern', 'northwestern', 'ohio-state', 'oklahoma', 'oklahoma-state', 'oregon', 'oregon-state', 'penn-state',
    'princeton', 'purdue', 'rice', 'rutgers', 'south-carolina', 'south-dakota', 'south-dakota-state', 'stanford',
    'syracuse', 'temple', 'tennessee', 'texas-am', 'tufts', 'tulane', 'uc-berkeley', 'uc-davis',
    'uc-irvine', 'uc-santa-barbara', 'ucsd', 'uchicago', 'ucla', 'uiuc', 'umass-amherst', 'umich',
    'unc', 'upenn', 'usc', 'utexas', 'utah', 'vermont', 'vanderbilt', 'virginia',
    'virginia-tech', 'wake-forest', 'washington-state', 'uw', 'washu', 'west-virginia', 'wisconsin', 'wyoming', 'yale',
    'alberta', 'british-columbia', 'mcgill', 'mcmaster', 'montreal', 'ottawa', 'queens', 'simon-fraser',
    'utoronto', 'waterloo', 'cambridge', 'edinburgh', 'imperial', 'kings-college-london', 'lse', 'manchester',
    'oxford', 'st-andrews', 'ucl', 'trinity-dublin', 'amsterdam', 'copenhagen', 'delft', 'epfl',
    'eth-zurich', 'heidelberg', 'ku-leuven', 'lmu-munich', 'paris-saclay', 'sorbonne', 'technical-university-munich', 'chinese-university-hong-kong',
    'hkust', 'iit-bombay', 'kaist', 'kyoto', 'national-taiwan', 'nus', 'peking', 'seoul-national',
    'technion', 'tel-aviv', 'tokyo', 'tsinghua', 'anu', 'auckland', 'cape-town', 'melbourne',
    'monash', 'new-south-wales', 'pontifical-catholic-chile', 'sao-paulo', 'sydney', 'unam'
  ];
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if p_school_key is null or not (p_school_key = any(v_allowed)) then
    raise exception 'That university is not available';
  end if;

  update public.profiles
  set university_school_key = p_school_key,
      updated_at = now()
  where id = auth.uid();

  return public.get_university_status();
end;
$$;

revoke all on function public.sync_university_email() from public;
drop function public.sync_university_email();
alter table public.profiles
  drop column university_email,
  drop column university_verified;
revoke all on function public.set_university(text) from public;
grant execute on function public.set_university(text) to authenticated;
