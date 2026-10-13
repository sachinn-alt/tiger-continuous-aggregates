# 🐯 Accelerate Dashboards with Timescale Continuous Aggregates (CAGGs) on Tiger Cloud

[![Tiger Cloud](https://img.shields.io/badge/Database-Tiger%20Cloud%20(TimescaleDB)-orange.svg)](https://console.cloud.tigerdata.com/)
[![Continuous Aggregates](https://img.shields.io/badge/Timescale-Continuous%20Aggregates-blue.svg)](https://www.tigerdata.com/docs/learn/continuous-aggregates)
[![Speedup](https://img.shields.io/badge/Query%20Performance-23x%20Faster-brightgreen.svg)]()
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

This project demonstrates how to accelerate real-time analytics and dashboard query latency by implementing **TimescaleDB Continuous Aggregates (CAGGs)** on **Tiger Cloud**. 

By pre-computing rollups and summary statistics (`time_bucket`, `AVG`, `MIN`, `MAX`, `COUNT`) in an incrementally refreshed materialized hypertable, query times were slashed from **4.27 ms to 0.18 ms** (a **>23x speedup**)!

---

## 🚀 Live Tiger Cloud Service Details

- **Service Name**: `cagg-analytics`
- **Service ID**: `kiwbq9oup6`
- **Project ID**: `fflhx4ep14`
- **Region**: `us-east-1` (AWS)
- **Engine**: TimescaleDB / PostgreSQL (Cloud Shared)
- **Console Dashboard**: [https://console.cloud.tigerdata.com/dashboard/services/kiwbq9oup6](https://console.cloud.tigerdata.com/dashboard/services/kiwbq9oup6)

---

## 🛠️ Step-by-Step Implementation

### 1. Create Base Telemetry Table
```sql
CREATE TABLE IF NOT EXISTS device_metrics (
    time TIMESTAMPTZ NOT NULL,
    device_id VARCHAR(50) NOT NULL,
    cpu_usage DOUBLE PRECISION,
    memory_usage DOUBLE PRECISION,
    temperature DOUBLE PRECISION
);
```

### 2. Convert Table to Timescale Hypertable
```sql
SELECT create_hypertable('device_metrics', 'time', if_not_exists => TRUE);
```

### 3. Ingest High-Frequency Time-Series Telemetry
Generated 10,000+ data points across 7 days for 5 IoT devices:
```sql
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
```

### 4. Create Continuous Aggregate (CAGG) View
Pre-compute hourly averages, minimums, maximums, and sample counts using `time_bucket('1 hour', time)`:
```sql
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
```

### 5. Configure Automated Background Refresh Policy
Automates incremental rollup computation in the background every 30 minutes:
```sql
SELECT add_continuous_aggregate_policy('hourly_metrics_summary',
    start_offset => INTERVAL '1 month',
    end_offset => INTERVAL '1 hour',
    schedule_interval => INTERVAL '30 minutes'
);
```

### 6. Refresh Historical Data
```sql
CALL refresh_continuous_aggregate('hourly_metrics_summary', NULL, NULL);
```

---

## ⚡ Performance Benchmark & Verification

### Benchmark Comparison: Raw Scan vs Continuous Aggregate

| Metric | Raw Hypertable Scan | Continuous Aggregate (CAGG) | Improvement |
| :--- | :--- | :--- | :--- |
| **Execution Time** | **4.271 ms** | **0.183 ms** | **>23x Faster** 🚀 |
| **Estimated Cost** | `599.05 .. 614.17` | `0.00 .. 19.32` | **97% Cost Reduction** |
| **Shared Buffers** | 95 buffers hit | 11 buffers hit | **88% Less I/O Load** |
| **Aggregation Mode** | On-the-fly Partial HashAggregate | Instant Materialized Scan | Zero CPU spike |

### Querying the Continuous Aggregate:
```sql
SELECT bucket, device_id, avg_cpu, max_cpu, min_cpu, avg_memory, avg_temperature, sample_count 
FROM hourly_metrics_summary 
ORDER BY bucket DESC, device_id 
LIMIT 5;
```

**Output:**
```text
 bucket                 | device_id | avg_cpu | max_cpu | min_cpu | avg_memory | avg_temperature | sample_count 
------------------------+-----------+---------+---------+---------+------------+-----------------+--------------
 2026-10-13 12:00:00+00 | sensor-1  | 56.82   | 82.89   | 20.81   | 55.17      | 39.68           | 12           
 2026-10-13 12:00:00+00 | sensor-2  | 48.76   | 72.12   | 15.76   | 46.18      | 38.91           | 12           
 2026-10-13 12:00:00+00 | sensor-3  | 49.36   | 81.71   | 17.17   | 57.51      | 36.34           | 11           
 2026-10-13 12:00:00+00 | sensor-4  | 49.48   | 67.17   | 25.15   | 51.36      | 32.86           | 12           
 2026-10-13 12:00:00+00 | sensor-5  | 49.36   | 84.10   | 21.47   | 57.19      | 36.44           | 12           
```

---

## 📊 Timescale Catalog Verification

```sql
SELECT view_name, materialization_hypertable_name, compression_enabled 
FROM timescaledb_information.continuous_aggregates;
```
```text
 view_name              | materialization_hypertable_name | compression_enabled 
------------------------+---------------------------------+---------------------
 hourly_metrics_summary | _materialized_hypertable_2      | f                   
```

```sql
SELECT job_id, application_name, schedule_interval 
FROM timescaledb_information.jobs 
WHERE application_name LIKE '%Continuous Aggregate%';
```
```text
 job_id | application_name                           | schedule_interval 
--------+--------------------------------------------+-------------------
 1001   | Refresh Continuous Aggregate Policy [1001] | 00:30:00          
```

---

## 📜 License
MIT License. Created by [sachinn-alt](https://github.com/sachinn-alt).
