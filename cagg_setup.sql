-- 1. Create base time-series table
CREATE TABLE IF NOT EXISTS device_metrics (
    time TIMESTAMPTZ NOT NULL,
    device_id VARCHAR(50) NOT NULL,
    cpu_usage DOUBLE PRECISION,
    memory_usage DOUBLE PRECISION,
    temperature DOUBLE PRECISION
);

-- 2. Convert into a TimescaleDB Hypertable partitioned by time
SELECT create_hypertable('device_metrics', 'time', if_not_exists => TRUE);

-- 3. Ingest synthetic real-time telemetry data (1 minute intervals over 7 days across 5 devices)
INSERT INTO device_metrics (time, device_id, cpu_usage, memory_usage, temperature)
SELECT
    time,
    'sensor-' || (row_number() over() % 5 + 1)::text as device_id,
    ROUND((random() * 70 + 15)::numeric, 2) as cpu_usage,
    ROUND((random() * 55 + 25)::numeric, 2) as memory_usage,
    ROUND((random() * 35 + 20)::numeric, 2) as temperature
FROM generate_series(
    NOW() - INTERVAL '7 days',
    NOW(),
    INTERVAL '1 minute'
) AS time;

-- 4. Create Continuous Aggregate (CAGG) for pre-computed hourly metrics
CREATE MATERIALIZED VIEW IF NOT EXISTS hourly_metrics_summary
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 hour', time) AS bucket,
    device_id,
    ROUND(AVG(cpu_usage)::numeric, 2) AS avg_cpu,
    ROUND(MAX(cpu_usage)::numeric, 2) AS max_cpu,
    ROUND(MIN(cpu_usage)::numeric, 2) AS min_cpu,
    ROUND(AVG(memory_usage)::numeric, 2) AS avg_memory,
    ROUND(AVG(temperature)::numeric, 2) AS avg_temperature,
    ROUND(MAX(temperature)::numeric, 2) AS max_temperature,
    COUNT(*) AS sample_count
FROM device_metrics
GROUP BY bucket, device_id
WITH NO DATA;

-- 5. Add Continuous Aggregate Refresh Policy (updates in background every 30 mins)
SELECT add_continuous_aggregate_policy('hourly_metrics_summary',
    start_offset => INTERVAL '1 month',
    end_offset => INTERVAL '1 hour',
    schedule_interval => INTERVAL '30 minutes'
);

-- 6. Manually refresh historical data to populate the materialized hypertable immediately
CALL refresh_continuous_aggregate('hourly_metrics_summary', NULL, NULL);
