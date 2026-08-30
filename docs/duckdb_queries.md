# Example DuckDB queries

Run these queries against a Corpus user database with the DuckDB command-line interface or another compatible tool.

## General statistics

### Total scrobbles
```sql
SELECT count(*) FROM scrobbles;
```

### Total unique artists
```sql
SELECT count(DISTINCT artist_name) FROM scrobbles;
```

## Top lists

### Top 10 artists
```sql
SELECT artist_name, count(*) as play_count
FROM scrobbles
GROUP BY artist_name
ORDER BY play_count DESC
LIMIT 10;
```

### Top 10 tracks
```sql
SELECT artist_name, track_name, count(*) as play_count
FROM scrobbles
GROUP BY artist_name, track_name
ORDER BY play_count DESC
LIMIT 10;
```

### Top 10 albums
```sql
SELECT artist_name, release_name, count(*) as play_count
FROM scrobbles
WHERE release_name IS NOT NULL AND release_name != ''
GROUP BY artist_name, release_name
ORDER BY play_count DESC
LIMIT 10;
```

### Top 10 labels
```sql
SELECT rm.label, count(*) as play_count
FROM scrobbles s
JOIN release_metadata rm ON s.release_mbid = rm.release_mbid
WHERE rm.label IS NOT NULL AND rm.label != ''
GROUP BY rm.label
ORDER BY play_count DESC
LIMIT 10;
```

## Time-based analysis

### Scrobbles per day for the last 30 days
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

## Maintenance and integrity

### Find duplicate scrobbles
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
