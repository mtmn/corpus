- `listened_at`: BIGINT (Unix timestamp)
- `track_name`: VARCHAR
- `artist_name`: VARCHAR
- `release_name`: VARCHAR
- `release_mbid`: VARCHAR
- `caa_release_mbid`: VARCHAR

## General Statistics

### Total number of scrobbles
```sql
SELECT count(*) FROM scrobbles;
```

### Artist diversity (Total unique artists)
```sql
SELECT count(DISTINCT artist_name) FROM scrobbles;
```

## Top Lists

### Top 10 Artists
```sql
SELECT artist_name, count(*) as play_count
FROM scrobbles
GROUP BY artist_name
ORDER BY play_count DESC
LIMIT 10;
```

### Top 10 Tracks
```sql
SELECT artist_name, track_name, count(*) as play_count
FROM scrobbles
GROUP BY artist_name, track_name
ORDER BY play_count DESC
LIMIT 10;
```

### Top 10 Albums
```sql
SELECT artist_name, release_name, count(*) as play_count
FROM scrobbles
WHERE release_name IS NOT NULL AND release_name != ''
GROUP BY artist_name, release_name
ORDER BY play_count DESC
LIMIT 10;
```

## Time-based Analysis

### Scrobbles per day (Last 30 days)
```sql
SELECT
    to_timestamp(listened_at)::DATE as date,
    count(*) as count
FROM scrobbles
WHERE to_timestamp(listened_at) > now() - INTERVAL '30 days'
GROUP BY date
ORDER BY date DESC;
```

### Scrobbles per month
```sql
SELECT
    date_trunc('month', to_timestamp(listened_at)) as month,
    count(*) as count
FROM scrobbles
GROUP BY month
ORDER BY month DESC;
```

### Listening activity by hour of day
```sql
SELECT
    extract('hour' from to_timestamp(listened_at)) as hour,
    count(*) as count
FROM scrobbles
GROUP BY hour
ORDER BY hour;
```

### Most active day of the week
```sql
SELECT
    dayname(to_timestamp(listened_at)) as day,
    count(*) as count
FROM scrobbles
GROUP BY day, dayofweek(to_timestamp(listened_at))
ORDER BY dayofweek(to_timestamp(listened_at));
```

## Maintenance & Integrity

### Find duplicate scrobbles (Same artist, track, and timestamp)
```sql
SELECT listened_at, artist_name, track_name, count(*)
FROM scrobbles
GROUP BY listened_at, artist_name, track_name
HAVING count(*) > 1;
```

### Recent scrobbles with human-readable timestamps
```sql
SELECT
    to_timestamp(listened_at) as time,
    artist_name,
    track_name
FROM scrobbles
ORDER BY listened_at DESC
LIMIT 20;
```

### Check MBID coverage
```sql
SELECT
    count(*) as total,
    count(release_mbid) FILTER (WHERE release_mbid != '') as with_mbid,
    (count(release_mbid) FILTER (WHERE release_mbid != '')::FLOAT / count(*)) * 100 as percentage
FROM scrobbles;
```
